//go:build windows

package main

import (
	"os/exec"
	"syscall"
)

const createNoWindow = 0x08000000

func hideWindow(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
}

// Windows 上没有控制台的进程收不到 Ctrl+C，只能直接结束（和 App 以前的做法一致）
func interrupt(cmd *exec.Cmd) { _ = cmd.Process.Kill() }
