//go:build !windows

package main

import (
	"os/exec"
	"syscall"
)

func hideWindow(*exec.Cmd) {}

func interrupt(cmd *exec.Cmd) { _ = cmd.Process.Signal(syscall.SIGTERM) }
