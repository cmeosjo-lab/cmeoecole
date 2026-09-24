//go:build windows

package main

import (
 "syscall"
 "time"
 "unsafe"
)

// Same-directory MoveFileExW with REPLACE_EXISTING|WRITE_THROUGH.
// No remove-then-rename fallback: failures leave the original in place.
func replaceDurably(src,dst string)error{
 from,err:=syscall.UTF16PtrFromString(src);if err!=nil{return err}
 to,err:=syscall.UTF16PtrFromString(dst);if err!=nil{return err}
 proc:=syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")
 var last error
 for n:=0;n<6;n++{
  ok,_,e:=proc.Call(uintptr(unsafe.Pointer(from)),uintptr(unsafe.Pointer(to)),uintptr(0x1|0x8))
  if ok!=0{return nil};last=e
  if e!=syscall.Errno(5)&&e!=syscall.Errno(32)&&e!=syscall.Errno(33){return e}
  time.Sleep(time.Duration(n+1)*25*time.Millisecond)
 }
 return last
}
