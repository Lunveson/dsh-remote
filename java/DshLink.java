import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.Base64;
import java.util.concurrent.*;

/**
 * dsh-link —— dsh 远程连接一键器（Java 版）
 *
 * 做三件事：
 *   ① 读 ~/.dsh/.credentials.yaml 里的 secret（浏览器会话签名密钥）
 *   ② 起一个 HTTP 代理：给每个请求自动注入 dsh 认证 cookie
 *   ③ 维护 adb reverse（手机的 19387 → 本代理），断了自动重做
 *
 * 用法：
 *   javac -encoding UTF-8 DshLink.java
 *   java DshLink [代理端口] [dsh端口] [adb路径]
 * 默认：代理监听 127.0.0.1:23554，转发到 127.0.0.1:19387，手机侧 reverse tcp:19387
 *
 * 手机打开 http://127.0.0.1:19387 即可（adb reverse 把它转到本代理）。
 */
public class DshLink {

    static final int BUF = 65536;
    static String adbPath = "adb";
    static int proxyPort = 23554;   // 本机监听（手机通过 adb reverse 访问）
    static int guiPort = 19387;     // dsh GUI
    static int phonePort = 19387;   // 手机侧端口（手机浏览器访问这个）
    static byte[] secret;

    public static void main(String[] args) throws Exception {
        if (args.length >= 1) proxyPort = Integer.parseInt(args[0]);
        if (args.length >= 2) guiPort = Integer.parseInt(args[1]);
        if (args.length >= 3) adbPath = args[2];

        secret = loadSecret();
        System.out.println("[dsh-link] secret 已读取 (" + secret.length + " 字节)");

        // ① 起代理
        startProxy();

        // ② 维护 adb reverse
        maintainReverse();

        System.out.println();
        System.out.println("========================================");
        System.out.println("  手机浏览器打开:  http://127.0.0.1:" + phonePort);
        System.out.println("  （App 内置 WebView 也加载这个地址）");
        System.out.println("========================================");
        System.out.println();
        System.out.println("按 Ctrl+C 退出。");

        Thread.currentThread().join();
    }

    // ==================== ① 读 secret ====================

    /** 从 ~/.dsh/.credentials.yaml 读 client-connection/browser-session 的 secret，并 base64url 解码。 */
    static byte[] loadSecret() throws Exception {
        String home = System.getProperty("user.home");
        Path p = Paths.get(home, ".dsh", ".credentials.yaml");
        if (!Files.exists(p)) throw new IOException("找不到 " + p);
        List<String> lines = Files.readAllLines(p, StandardCharsets.UTF_8);

        boolean inRecord = false;
        String raw = null;
        for (String line : lines) {
            String s = line.trim();
            if (s.startsWith("client-connection/browser-session:")) { inRecord = true; continue; }
            if (inRecord) {
                if (s.startsWith("secret:")) { raw = s.substring("secret:".length()).trim(); break; }
                if (!line.isEmpty() && !line.startsWith(" ") && !line.startsWith("\t") && !s.startsWith("kind:")) {
                    inRecord = false;
                }
            }
        }
        if (raw == null) throw new IOException("credentials 里没找到 secret");
        // ★ dsh 用的是 base64url 解码后的字节作为 HMAC key ★
        return Base64.getUrlDecoder().decode(pad(raw));
    }

    static String pad(String s) {
        int r = s.length() % 4;
        if (r == 0) return s;
        StringBuilder sb = new StringBuilder(s);
        for (int i = 0; i < 4 - r; i++) sb.append('=');
        return sb.toString();
    }

    // ==================== cookie 签名 ====================

    static String b64url(byte[] data) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(data);
    }

    /** cookie 名 = dsh-auth-<b64url(sha256(authority))> */
    static String cookieName(String authority) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        return "dsh-auth-" + b64url(md.digest(authority.getBytes(StandardCharsets.UTF_8)));
    }

    /** cookie 值 = v1.<b64url(payload)>.<b64url(HMAC-SHA256(secret, body))> */
    static String makeCookie(String authority) throws Exception {
        long now = System.currentTimeMillis();
        long exp = now + 30L * 24 * 3600 * 1000;
        // ★ 键顺序必须和 JS 的 JSON.stringify 一致 ★
        String json = "{\"version\":1,\"authority\":\"" + authority + "\",\"issuedAt\":" + now
                + ",\"expiresAt\":" + exp + "}";
        String body = b64url(json.getBytes(StandardCharsets.UTF_8));
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret, "HmacSHA256"));
        String sig = b64url(mac.doFinal(body.getBytes(StandardCharsets.UTF_8)));
        return cookieName(authority) + "=v1." + body + "." + sig;
    }

    // ==================== ② HTTP 代理 ====================

    static void startProxy() throws Exception {
        ServerSocket srv = new ServerSocket(proxyPort, 64, InetAddress.getByName("127.0.0.1"));
        Thread t = new Thread(() -> {
            ExecutorService pool = Executors.newCachedThreadPool();
            System.out.println("[dsh-link] 代理监听 127.0.0.1:" + proxyPort + " -> 127.0.0.1:" + guiPort);
            while (true) {
                try {
                    Socket c = srv.accept();
                    pool.submit(() -> handle(c));
                } catch (Exception ignored) { }
            }
        });
        t.setDaemon(true);
        t.start();
    }

    static void handle(Socket client) {
        Socket back = null;
        try {
            client.setSoTimeout(15000);
            InputStream in = client.getInputStream();
            ByteArrayOutputStream headBuf = new ByteArrayOutputStream();
            int state = 0, b;
            while ((b = in.read()) != -1) {
                headBuf.write(b);
                // 检测 \r\n\r\n
                if ((state == 0 || state == 2) && b == '\r') state++;
                else if ((state == 1 || state == 3) && b == '\n') state++;
                else state = 0;
                if (state == 4) break;
                if (headBuf.size() > 262144) break;
            }
            byte[] headBytes = headBuf.toByteArray();
            if (headBytes.length == 0) { client.close(); return; }

            String headText = new String(headBytes, StandardCharsets.ISO_8859_1);
            String authority = headerValue(headText, "host");
            if (authority == null) { client.close(); return; }
            String cookie = makeCookie(authority);

            // 注入/覆盖 Cookie，插在空行之前
            String[] lines = headText.split("\r\n", -1);
            boolean isWebSocket = headText.toLowerCase().contains("upgrade: websocket");
            StringBuilder sb = new StringBuilder();
            boolean cookieSet = false;
            boolean connSeen = false;
            for (int i = 0; i < lines.length; i++) {
                String ln = lines[i];
                if (ln.isEmpty()) {
                    if (!cookieSet) sb.append("Cookie: ").append(cookie).append("\r\n");
                    // ★非 WebSocket：强制 Connection: close★
                    //   否则 keep-alive 复用连接时，后续请求不经过我们（拿不到 cookie）→ 401
                    if (!connSeen && !isWebSocket) sb.append("Connection: close\r\n");
                    sb.append("\r\n");
                    for (int j = i + 1; j < lines.length; j++) {
                        if (j > i + 1) sb.append("\r\n");
                        sb.append(lines[j]);
                    }
                    break;
                }
                String low = ln.toLowerCase();
                if (low.startsWith("cookie:")) {
                    sb.append("Cookie: ").append(cookie).append("\r\n");
                    cookieSet = true;
                } else if (low.startsWith("connection:")) {
                    connSeen = true;
                    if (isWebSocket) {
                        sb.append(ln).append("\r\n");   // WebSocket 保留（要升级长连接）
                    } else {
                        sb.append("Connection: close\r\n");
                    }
                } else {
                    sb.append(ln).append("\r\n");
                }
            }
            byte[] newHead = sb.toString().getBytes(StandardCharsets.ISO_8859_1);

            client.setSoTimeout(0);
            back = new Socket("127.0.0.1", guiPort);
            back.getOutputStream().write(newHead);
            back.getOutputStream().flush();

            Socket bb = back;
            Thread up = new Thread(() -> pipe(client, bb));
            up.setDaemon(true);
            up.start();
            pipe(back, client);
        } catch (Exception e) {
            // 静默
        } finally {
            close(client);
            close(back);
        }
    }

    static String headerValue(String head, String name) {
        for (String ln : head.split("\r\n")) {
            int c = ln.indexOf(':');
            if (c > 0 && ln.substring(0, c).trim().equalsIgnoreCase(name)) {
                return ln.substring(c + 1).trim();
            }
        }
        return null;
    }

    static void pipe(Socket from, Socket to) {
        try {
            InputStream in = from.getInputStream();
            OutputStream out = to.getOutputStream();
            byte[] buf = new byte[BUF];
            int n;
            while ((n = in.read(buf)) != -1) {
                out.write(buf, 0, n);
                out.flush();
            }
        } catch (Exception ignored) {
        } finally {
            close(from);
            close(to);
        }
    }

    static void close(Socket s) {
        if (s != null) try { s.close(); } catch (Exception ignored) { }
    }

    // ==================== ③ 维护 adb reverse ====================

    /**
     * ③ 维护 adb reverse —— 并且★自动重连手机★
     *
     * 背景：电脑进 S0 现代待机时 WiFi 会省电掉线，导致无线 adb 断开。
     * 唤醒后 adb 不会自己回来（要 kill-server 重新做 mDNS 发现），
     * 所以这里做三级恢复：
     *   第 1 级：adb reconnect offline          （轻，试一下）
     *   第 2 级：kill-server + start-server     （重，重新发现设备）
     *   第 3 级：持续等待                       （退避，别死循环刷）
     */
    static void maintainReverse() {
        Thread t = new Thread(() -> {
            boolean lastOk = false;
            int failCount = 0;          // 连续"看不到设备"的次数

            while (true) {
                try {
                    boolean hasDevice = hasRealDevice(runAdb("devices"));

                    if (hasDevice) {
                        if (failCount > 0) {
                            System.out.println("[dsh-link] 手机回来了");
                        }
                        failCount = 0;
                        ensureReverse(lastOk);
                        lastOk = true;
                    } else {
                        failCount++;
                        if (lastOk || failCount == 1) {
                            System.out.println("[dsh-link] 手机断开了，尝试重连…");
                        }
                        lastOk = false;

                        // ---- 第 1 级：让 adb 自己重连（第 2 次失败时试一次）----
                        if (failCount == 2) {
                            runAdb("reconnect", "offline");
                        }
                        // ---- 第 2 级：重启 adb server 重新发现（第 4 次起，每 3 轮一次）----
                        else if (failCount >= 4 && (failCount - 4) % 3 == 0) {
                            System.out.println("[dsh-link] 重启 adb server 重新发现设备…");
                            runAdb("kill-server");
                            Thread.sleep(1000);
                            runAdb("start-server");
                            Thread.sleep(4000);
                        }
                    }
                } catch (Exception ignored) { }
                try { Thread.sleep(3000); } catch (InterruptedException e) { return; }
            }
        });
        t.setDaemon(true);
        t.start();
    }

    /** 判断 adb devices 输出里是否有【真正可用】的设备（排除 offline / unauthorized / 空行）。 */
    static boolean hasRealDevice(String devs) {
        if (devs == null) return false;
        for (String ln : devs.split("\n")) {
            String s = ln.trim();
            if (s.isEmpty()) continue;
            if (s.startsWith("List of devices")) continue;
            if (s.startsWith("*")) continue;            // daemon 启动信息
            String[] parts = s.split("\\s+");
            if (parts.length >= 2 && parts[1].equals("device")) return true;
        }
        return false;
    }

    /** 确保 adb reverse 存在（缺失就重建）。 */
    static void ensureReverse(boolean lastOk) {
        String want = "tcp:" + phonePort + " tcp:" + proxyPort;
        String list = runAdb("reverse", "--list");
        if (list == null || !list.contains(want)) {
            runAdb("reverse", "tcp:" + phonePort, "tcp:" + proxyPort);
            String after = runAdb("reverse", "--list");
            if (after != null && after.contains(want)) {
                System.out.println("[dsh-link] adb reverse 已建立: 手机 " + phonePort + " -> 本机 " + proxyPort);
            }
        } else if (!lastOk) {
            System.out.println("[dsh-link] adb reverse 正常");
        }
    }

    static String runAdb(String... args) {
        try {
            List<String> cmd = new ArrayList<>();
            cmd.add(adbPath);
            cmd.addAll(Arrays.asList(args));
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            p.waitFor(6, TimeUnit.SECONDS);
            return out;
        } catch (Exception e) {
            return null;
        }
    }
}
