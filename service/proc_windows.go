//go:build windows

package main

import (
	"log"
	"os/exec"
	"sync"
	"syscall"

	"golang.org/x/sys/windows"
)

const (
	createNewConsole      = 0x00000010
	createNewProcessGroup = 0x00000200
)

var (
	kernel32                     = windows.NewLazySystemDLL("kernel32.dll")
	procAttachConsole            = kernel32.NewProc("AttachConsole")
	procFreeConsole              = kernel32.NewProc("FreeConsole")
	procSetConsoleCtrlHandler    = kernel32.NewProc("SetConsoleCtrlHandler")
	procGenerateConsoleCtrlEvent = kernel32.NewProc("GenerateConsoleCtrlEvent")
	consoleMu                    sync.Mutex
)

// 内核放在独立的（隐藏的）控制台和进程组里，停止时才能给它发 Ctrl+Break 让它正常退出
func hideWindow(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNewConsole | createNewProcessGroup}
}

// interrupt 让内核正常退出：附加到它的控制台发 Ctrl+Break（sing-box 收到后会关闭 TUN 网卡再退出）。
// 以前是直接强制结束，内核来不及删网卡，留下的残留网卡会让下次创建同名网卡失败（卡 15 秒后报
// “Cannot create a file when that file already exists”）。发不出去时退回强制结束
func interrupt(cmd *exec.Cmd) {
	consoleMu.Lock()
	defer consoleMu.Unlock()
	pid := uintptr(cmd.Process.Pid)
	procFreeConsole.Call()
	if r, _, _ := procAttachConsole.Call(pid); r == 0 {
		_ = cmd.Process.Kill()
		return
	}
	procSetConsoleCtrlHandler.Call(0, 1) // 服务自己忽略这个信号
	r, _, _ := procGenerateConsoleCtrlEvent.Call(windows.CTRL_BREAK_EVENT, pid)
	procFreeConsole.Call()
	if r == 0 {
		_ = cmd.Process.Kill()
	}
}

// cleanupTunGhosts 删除不在线的、名字以 Koyun 开头的网卡（内核异常退出留下的残留 TUN 网卡）。
// 只删“不在线”的，正在用的和别的 VPN 软件的网卡都不碰。需要管理员 / SYSTEM 权限
func cleanupTunGhosts() {
	ps := `$ErrorActionPreference='SilentlyContinue'; ` +
		`Get-PnpDevice -Class Net | Where-Object { $_.Status -ne 'OK' -and $_.FriendlyName -like 'Koyun*' } | ` +
		`ForEach-Object { pnputil /remove-device $_.InstanceId | Out-Null; $_.FriendlyName }`
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", ps)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	out, err := cmd.Output()
	if err == nil && len(out) > 0 {
		log.Printf("removed stale TUN adapters: %s", out)
	}
}
