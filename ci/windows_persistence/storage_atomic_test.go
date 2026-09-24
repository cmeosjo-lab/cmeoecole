package main
import("bytes";"encoding/json";"errors";"os";"path/filepath";"sync";"testing")
func TestSafeJSONRoundTrip(t *testing.T){
 p:=filepath.Join(t.TempDir(),"state.json");if e:=safeJSONWrite(p,[]byte(`{"version":1,"students":[]}`));e!=nil{t.Fatal(e)}
 b,src,e:=safeJSONRead(p,nil);if e!=nil||src!=""{t.Fatal(src,e)};if e=verifyJSON(b);e!=nil{t.Fatal(e)}
}
func TestRecoveryAfterTruncation(t *testing.T){
 p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`{"generation":1}`));safeJSONWrite(p,[]byte(`{"generation":2}`));os.WriteFile(p,[]byte(`{"broken":`),0600)
 b,src,e:=safeJSONRead(p,nil);if e!=nil||src==""{t.Fatal(src,e)};if !bytes.Contains(b,[]byte(`"generation": 1`)){t.Fatal(string(b))}
 files,_:=filepath.Glob(p+".corrompu-*");if len(files)!=1{t.Fatal("broken generation not preserved")}
}
func TestRecoveryAfterChecksumTampering(t *testing.T){
 p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`{"n":1}`));safeJSONWrite(p,[]byte(`{"n":2}`));b,_:=os.ReadFile(p);b=bytes.Replace(b,[]byte(`"n": 2`),[]byte(`"n": 9`),1);os.WriteFile(p,b,0600)
 _,src,e:=safeJSONRead(p,nil);if e!=nil||src==""{t.Fatal(src,e)}
}
func TestInvalidWritePreservesLiveFile(t *testing.T){
 p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`[]`));old,_:=os.ReadFile(p);if safeJSONWrite(p,[]byte(`{"invalid"`))==nil{t.Fatal("accepted malformed JSON")};b,_:=os.ReadFile(p);if !bytes.Equal(b,old){t.Fatal("live file changed")}
}
func TestNoSilentResetAfterAllCopiesCorrupt(t *testing.T){
 p:=filepath.Join(t.TempDir(),"state.json");os.WriteFile(p,[]byte(`broken`),0600);_,_,e:=safeJSONRead(p,nil);if e==nil||errors.Is(e,os.ErrNotExist){t.Fatal("corruption treated as empty database")};if safeJSONWrite(p,[]byte(`[]`))==nil{t.Fatal("overwrote corrupt state")}
}
func TestMissingFileIsDistinguished(t *testing.T){_,_,e:=safeJSONRead(filepath.Join(t.TempDir(),"absent"),nil);if !errors.Is(e,os.ErrNotExist){t.Fatal(e)}}
func TestRecoverMissingPrimary(t *testing.T){p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`[]`));safeJSONWrite(p,[]byte(`[1]`));os.Remove(p);b,src,e:=safeJSONRead(p,nil);if e!=nil||src==""||string(b)!="[]"{t.Fatal(src,e,string(b))}}
func TestRejectInvalidRecoveryEnvelope(t *testing.T){p:=filepath.Join(t.TempDir(),"state.json");os.WriteFile(p,[]byte(`!`),0600);os.WriteFile(p+".recovery.json",[]byte(`{"sha256":"bad","data":"W10="}`),0600);_,_,e:=safeJSONRead(p,nil);if e==nil{t.Fatal("accepted bad backup")}}
func TestSchemaValidatorAppliedToBackup(t *testing.T){p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`[1]`));safeJSONWrite(p,[]byte(`[2]`));check:=func(b []byte)error{var m map[string]any;return json.Unmarshal(b,&m)};if _,_,e:=safeJSONRead(p,check);e==nil{t.Fatal("wrong schema accepted")}}
func TestConcurrentReadersNeverSeePartialJSON(t *testing.T){
 p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`{"n":0}`));var wg sync.WaitGroup
 for i:=0;i<12;i++{wg.Add(1);go func(){defer wg.Done();for j:=0;j<20;j++{b,e:=os.ReadFile(p);if e!=nil||verifyJSON(b)!=nil{t.Errorf("partial read: %v",e)}}}()}
 for j:=0;j<30;j++{b,_:=json.Marshal(map[string]int{"n":j});if e:=safeJSONWrite(p,b);e!=nil{t.Fatal(e)}};wg.Wait()
}
func TestFailedReplacementPreservesTarget(t *testing.T){p:=filepath.Join(t.TempDir(),"target");os.Mkdir(p,0700);os.WriteFile(filepath.Join(p,"keep"),[]byte("safe"),0600);if atomicWriteFile(p,[]byte("new"))==nil{t.Fatal("unexpected replacement of directory")};if b,e:=os.ReadFile(filepath.Join(p,"keep"));e!=nil||string(b)!="safe"{t.Fatal("old target lost")}}
func TestMissingPrimaryAndCorruptBackupIsNotFirstRun(t *testing.T){p:=filepath.Join(t.TempDir(),"state.json");os.WriteFile(p+".bak",[]byte(`broken`),0600);_,_,e:=safeJSONRead(p,nil);if e==nil||errors.Is(e,os.ErrNotExist){t.Fatal("would reset existing damaged data",e)}}
func TestWrongObjectSchemaRecoversPreviousGeneration(t *testing.T){p:=filepath.Join(t.TempDir(),"state.json");safeJSONWrite(p,[]byte(`{"students":[]}`));safeJSONWrite(p,[]byte(`{"other":1}`));_,src,e:=safeJSONRead(p,func(b []byte)error{return validateObjectKeys(b,"students")});if e!=nil||src==""{t.Fatal(src,e)}}
