//go:build !windows

package main
import("os";"path/filepath")
func replaceDurably(src,dst string)error{
 if err:=os.Rename(src,dst);err!=nil{return err}
 f,err:=os.Open(filepath.Dir(dst));if err!=nil{return err};defer f.Close();return f.Sync()
}
