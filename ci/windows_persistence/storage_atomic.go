package main

// Shared durable storage for Principal and Prof. Never truncate the live file.
// Writes stay on the same volume; the previous valid generation is retained.
import (
 "bytes"
 "crypto/sha256"
 "encoding/json"
 "errors"
 "fmt"
 "io"
 "os"
 "path/filepath"
 "strings"
 "sync"
 "time"
)
var durableIOMu sync.Mutex
const integrityKey = "_gestcours_sha256"
func durableDigest(b []byte) string { return fmt.Sprintf("%x",sha256.Sum256(b)) }
func sealJSON(b []byte)([]byte,error){
 if !json.Valid(b)||bytes.Equal(bytes.TrimSpace(b),[]byte("null")){return nil,errors.New("JSON vide ou invalide : écriture annulée")}
 if len(bytes.TrimSpace(b))==0||bytes.TrimSpace(b)[0]!='{'{return b,nil}
 var obj map[string]json.RawMessage
 if err:=json.Unmarshal(b,&obj);err!=nil{return nil,err}
 delete(obj,integrityKey)
 canonical,err:=json.Marshal(obj);if err!=nil{return nil,err}
 obj[integrityKey],_=json.Marshal(durableDigest(canonical))
 return json.MarshalIndent(obj,"","  ")
}
func verifyJSON(b []byte)error{
 if !json.Valid(b)||bytes.Equal(bytes.TrimSpace(b),[]byte("null")){return errors.New("JSON vide ou endommagé")}
 if bytes.TrimSpace(b)[0]!='{'{return nil}
 var obj map[string]json.RawMessage
 if err:=json.Unmarshal(b,&obj);err!=nil{return err}
 raw,ok:=obj[integrityKey];if !ok{return nil}
 var digest string;if err:=json.Unmarshal(raw,&digest);err!=nil{return err}
 delete(obj,integrityKey);canonical,err:=json.Marshal(obj);if err!=nil{return err}
 if digest!=durableDigest(canonical){return errors.New("empreinte de contrôle JSON incorrecte")};return nil
}
func atomicWriteFile(path string,b []byte)(err error){
 if err=os.MkdirAll(filepath.Dir(path),0700);err!=nil{return err}
 f,err:=os.CreateTemp(filepath.Dir(path),"."+filepath.Base(path)+".tmp-*");if err!=nil{return err}
 name:=f.Name();defer func(){_=f.Close();_=os.Remove(name)}()
 if err=f.Chmod(0600);err!=nil{return err}
 n,err:=f.Write(b);if err!=nil{return err};if n!=len(b){return io.ErrShortWrite}
 if err=f.Sync();err!=nil{return err};if err=f.Close();err!=nil{return err}
 actual,err:=os.ReadFile(name);if err!=nil{return err}
 if !bytes.Equal(actual,b){return errors.New("vérification du fichier temporaire impossible")}
 if err=replaceDurably(name,path);err!=nil{return err};return nil
}
type recoveryGeneration struct { SHA256 string `json:"sha256"`; Data []byte `json:"data"` }
func safeJSONWrite(path string,data []byte)error{
 durableIOMu.Lock();defer durableIOMu.Unlock()
 b,err:=sealJSON(data);if err!=nil{return err}
 old,readErr:=os.ReadFile(path)
 if readErr==nil{
  if err=verifyJSON(old);err!=nil{return fmt.Errorf("%s : ancienne copie invalide, restauration nécessaire : %w",filepath.Base(path),err)}
  if bytes.Equal(old,b){return nil}
  recovery,_:=json.Marshal(recoveryGeneration{SHA256:durableDigest(old),Data:old})
  if err=atomicWriteFile(path+".recovery.json",recovery);err!=nil{return fmt.Errorf("copie de secours : %w",err)}
  if err=atomicWriteFile(path+".bak",old);err!=nil{return fmt.Errorf("sauvegarde précédente : %w",err)}
 }else if !errors.Is(readErr,os.ErrNotExist){return readErr}
 return atomicWriteFile(path,b)
}
func safeJSONRead(path string,validate func([]byte)error)([]byte,string,error){
 durableIOMu.Lock();defer durableIOMu.Unlock()
 check:=func(b []byte)error{if err:=verifyJSON(b);err!=nil{return err};if validate!=nil{return validate(b)};return nil}
 original,err:=os.ReadFile(path);firstErr:=err
 if err!=nil&&!errors.Is(err,os.ErrNotExist){return nil,"",fmt.Errorf("lecture protégée %s : %w",filepath.Base(path),err)}
 if err==nil{firstErr=check(original);if firstErr==nil{return original,"",nil}}
 existed:=!errors.Is(err,os.ErrNotExist)
 for _,candidate:=range []string{path+".recovery.json",path+".bak"}{
  b,e:=os.ReadFile(candidate);if e!=nil{continue};existed=true
  if strings.HasSuffix(candidate,".recovery.json"){
   var gen recoveryGeneration;if json.Unmarshal(b,&gen)!=nil||gen.SHA256!=durableDigest(gen.Data){continue};b=gen.Data
  }
  if check(b)!=nil{continue}
  if err==nil{if e=atomicWriteFile(path+".corrompu-"+time.Now().Format("20060102-150405.000000000"),original);e!=nil{return nil,"",e}}
  if e=atomicWriteFile(path,b);e!=nil{return nil,"",e};return b,filepath.Base(candidate),nil
 }
 if !existed{return nil,"",os.ErrNotExist}
 if firstErr==nil||errors.Is(firstErr,os.ErrNotExist){firstErr=errors.New("fichier principal absent et copies de secours invalides")}
 return nil,"",fmt.Errorf("%s : %w ; aucune restauration automatique sûre",filepath.Base(path),firstErr)
}
func validateObjectKeys(b []byte,keys ...string)error{
 var raw map[string]json.RawMessage;if err:=json.Unmarshal(b,&raw);err!=nil{return err}
 if raw==nil{return errors.New("objet JSON absent")}
 for _,key:=range keys{if _,ok:=raw[key];!ok{return fmt.Errorf("champ obligatoire absent : %s",key)}};return nil
}
