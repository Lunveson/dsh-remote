package com.rptchat.dshremote;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * dsh-remote 手机端
 *
 * 一个 WebView，连电脑上的 dsh GUI。
 * 链路：WebView → http://127.0.0.1:19387 → adb reverse → 电脑 dsh-link 代理 → dsh
 *
 * 电脑端要先把 dsh-link 跑起来（双击 启动-静默.vbs）。
 */
public class MainActivity extends Activity {

    /** 默认地址（adb reverse 把手机的 19387 转到电脑） */
    static final String DEFAULT_URL = "http://127.0.0.1:19387";

    /** ★调试开关：true = 强制用 WebView（方便 adb 远程调试看 Console/Network）★ */
    static final boolean FORCE_WEBVIEW = true;

    /**
     * ★polyfill：给旧 WebView(103) 补上新 API★
     * dsh 前端用了 Promise.withResolvers(Chrome119+) 和 AbortSignal.any(Chrome116+)，
     * 旧内核没有 → JS 崩溃 → 连不上。注入这段就能补上。
     */
    static final String POLYFILL = "(function(){"
            + "if(typeof Promise.withResolvers!=='function'){"
            + "Promise.withResolvers=function(){var r,j;var p=new Promise(function(a,b){r=a;j=b;});"
            + "return {promise:p,resolve:r,reject:j};};}"
            + "if(typeof AbortSignal.any!=='function'){"
            + "AbortSignal.any=function(sigs){var c=new AbortController();"
            + "for(var i=0;i<sigs.length;i++){var s=sigs[i];"
            + "if(s.aborted){c.abort();return c.signal;}"
            + "s.addEventListener('abort',function(){c.abort();},{once:true});}"
            + "return c.signal;};}"
            + "})();";

    private WebView web;
    private LinearLayout errorView;
    private TextView errMsg;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        // ★ 开 WebView 远程调试（adb forward 后可用 chrome://inspect 看 Console/Network）★
        try { WebView.setWebContentsDebuggingEnabled(true); } catch (Throwable ignored) { }

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF14141C);

        // ===== WebView =====
        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        web.setBackgroundColor(0xFF14141C);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest req) {
                String url = req.getUrl().toString();
                // ★只拦主文档：下载 HTML → 在 <head> 注入 polyfill → 返回给 WebView★
                if (url.equals(DEFAULT_URL + "/") || url.equals(DEFAULT_URL)) {
                    try {
                        java.net.HttpURLConnection conn =
                                (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
                        conn.setConnectTimeout(15000);
                        conn.setReadTimeout(25000);
                        conn.setRequestProperty("Host", "127.0.0.1:19387");
                        java.io.InputStream in = conn.getInputStream();
                        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                        byte[] buf = new byte[16384];
                        int n;
                        while ((n = in.read(buf)) != -1) bo.write(buf, 0, n);
                        in.close();
                        String html = new String(bo.toByteArray(), java.nio.charset.StandardCharsets.UTF_8);
                        if (html.contains("<head>")) {
                            html = html.replace("<head>", "<head><script>" + POLYFILL + "</script>");
                        } else {
                            html = "<script>" + POLYFILL + "</script>" + html;
                        }
                        return new WebResourceResponse("text/html", "utf-8",
                                new java.io.ByteArrayInputStream(
                                        html.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
                    } catch (Exception e) {
                        return null;   // 拦截失败就正常加载，下面会报错提示
                    }
                }
                return null;
            }

            @Override
            public void onPageFinished(WebView v, String url) {
                hideError();
            }

            @Override
            public void onReceivedError(WebView v, int errorCode, String description, String failingUrl) {
                // 主框架失败才提示（子资源失败不管）
                if (failingUrl != null && failingUrl.equals(DEFAULT_URL + "/")
                        || (failingUrl != null && failingUrl.startsWith(DEFAULT_URL))) {
                    showError(description);
                }
            }
        });
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));

        // ===== 错误提示层（连不上时显示） =====
        errorView = new LinearLayout(this);
        errorView.setOrientation(LinearLayout.VERTICAL);
        errorView.setGravity(Gravity.CENTER);
        errorView.setBackgroundColor(0xFF14141C);
        errorView.setPadding(dp(32), dp(32), dp(32), dp(32));

        TextView title = new TextView(this);
        title.setText("连不上电脑");
        title.setTextColor(0xFFFFE08A);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        title.setGravity(Gravity.CENTER);
        errorView.addView(title);

        errMsg = new TextView(this);
        errMsg.setTextColor(0xFF9AA3B5);
        errMsg.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        errMsg.setGravity(Gravity.CENTER);
        errMsg.setPadding(0, dp(16), 0, dp(24));
        errMsg.setText("检查这几件事：\n\n"
                + "1. 电脑上双击了 启动-静默.vbs 吗？\n"
                + "   （dsh-link 要在跑）\n\n"
                + "2. 手机和电脑的 adb 连着吗？\n"
                + "   （无线调试 / USB）\n\n"
                + "3. 电脑上的 dsh 开着吗？\n\n"
                + "地址：" + DEFAULT_URL);
        errorView.addView(errMsg);

        Button retry = new Button(this);
        retry.setText("重试");
        retry.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        retry.setOnClickListener(v -> {
            hideError();
            web.loadUrl(DEFAULT_URL);
        });
        errorView.addView(retry);

        root.addView(errorView, new FrameLayout.LayoutParams(-1, -1));
        errorView.setVisibility(View.GONE);

        setContentView(root);

        // ★ 检测系统 WebView 版本 ★
        //   dsh 前端用了 Promise.withResolvers(Chrome119+) / AbortSignal.any(Chrome116+)
        //   WebView 太旧会 JS 报错 → WebSocket 连不上 → 改用系统浏览器打开
        if (isWebViewTooOld()) {
            // 优先：Chrome Custom Tabs（用系统浏览器内核，无地址栏，像内嵌）
            try {
                androidx.browser.customtabs.CustomTabsIntent.Builder b =
                        new androidx.browser.customtabs.CustomTabsIntent.Builder();
                b.setShowTitle(false);
                b.setUrlBarHidingEnabled(true);
                androidx.browser.customtabs.CustomTabsIntent ct = b.build();
                ct.intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                ct.launchUrl(this, android.net.Uri.parse(DEFAULT_URL));
                showDowngradeNotice("Custom Tabs");
                return;
            } catch (Throwable ignored) { }

            // 回退：普通浏览器打开
            try {
                android.content.Intent i = new android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse(DEFAULT_URL));
                i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
                showDowngradeNotice("系统浏览器");
                return;
            } catch (Exception ignored) {
                // 打不开就继续用 WebView
            }
        }

        web.loadUrl(DEFAULT_URL);
    }

    /** 显示"WebView 太旧，已改用外部内核"的提示 */
    private void showDowngradeNotice(String via) {
        errMsg.setText("系统 WebView 版本太旧（" + webViewVersion() + "）\n\n"
                + "dsh 界面需要 Chrome 116 以上，\n"
                + "所以已经用「" + via + "」打开了（用的浏览器内核）。\n\n"
                + "想用这个 App 直接内嵌显示的话：\n"
                + "更新【Android System WebView】到 116+ 即可。\n\n"
                + "地址：" + DEFAULT_URL);
        errorView.setVisibility(View.VISIBLE);
    }

    /** 取当前 WebView 版本号（拿不到就返回空） */
    private String webViewVersion() {
        try {
            android.content.pm.PackageInfo pi = WebView.getCurrentWebViewPackage();
            if (pi != null && pi.versionName != null) return pi.versionName;
        } catch (Throwable ignored) { }
        return "未知";
    }

    /** WebView 主版本 < 116 就认为太旧 */
    private boolean isWebViewTooOld() {
        if (FORCE_WEBVIEW) return false;   // ★调试开关：强制用 WebView，方便远程调试★
        try {
            android.content.pm.PackageInfo pi = WebView.getCurrentWebViewPackage();
            if (pi == null || pi.versionName == null) return false;
            String[] parts = pi.versionName.split("\\.");
            int major = Integer.parseInt(parts[0]);
            return major < 116;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private void showError(String desc) {
        if (desc != null && !desc.isEmpty()) {
            errMsg.setText(errMsg.getText() + "\n\n（" + desc + "）");
        }
        errorView.setVisibility(View.VISIBLE);
    }

    private void hideError() {
        errorView.setVisibility(View.GONE);
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (errorView.getVisibility() == View.VISIBLE) {
                errorView.setVisibility(View.GONE);
                return true;
            }
            if (web.canGoBack()) {
                web.goBack();
                return true;
            }
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
