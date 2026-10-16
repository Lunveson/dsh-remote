# ============================================================
#  blackout-run —— 显示全屏黑窗口（由 blackout.ps1 启动）
#
#  ★修复记录★
#   上一版问题：MainWindowHandle = 0（窗口根本没创建出来）
#   原因：
#     ① Application.Run() 没传主窗体 → 消息循环没挂到窗口上
#     ② Opacity 从 0 淡入，Timer 没生效 → 永久透明
#     ③ 依赖 Show() + Timer，链路太长
#   改法：直接 Application.Run($form)；不做动画；窗口就是不透明的。
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$screens = [System.Windows.Forms.Screen]::AllScreens
$primary = $null

foreach ($s in $screens) {
  $f = New-Object System.Windows.Forms.Form
  $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $f.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
  $f.Bounds          = $s.Bounds
  $f.BackColor       = [System.Drawing.Color]::Black
  $f.TopMost         = $true
  $f.ShowInTaskbar   = $false
  $f.MinimizeBox     = $false
  $f.MaximizeBox     = $false
  $f.ControlBox      = $false
  $f.Cursor          = [System.Windows.Forms.Cursors]::Default

  # 吞掉 Alt+F4（要关只能杀进程）
  $f.Add_FormClosing({ param($sender, $e) $e.Cancel = $true })

  if ($null -eq $primary) {
    $primary = $f          # 主屏这个交给消息循环
  } else {
    $f.Show()              # 其他屏自己显示
  }
}

if ($null -eq $primary) { exit 1 }

# ★关键：把主窗体交给 Run()（不带参数的 Run() 不会显示任何窗口）★
[System.Windows.Forms.Application]::Run($primary)
