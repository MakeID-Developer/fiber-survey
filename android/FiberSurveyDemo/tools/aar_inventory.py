#!/usr/bin/env python3
"""Read-only AAR/JAR/class metadata, no JVM, compiler, Gradle, native load, or packaging."""
from pathlib import Path
import hashlib, io, json, struct, zipfile

ROOT=Path(__file__).resolve().parents[1]
FILES=['MakeID_XCFiberCheckLib_1.0.aar','makeid_bleconnectlib_1.1.aar']

def class_info(data):
    pos=8
    def read(fmt):
        nonlocal pos
        value=struct.unpack_from('>'+fmt,data,pos)[0];pos+=struct.calcsize('>'+fmt);return value
    count=read('H');pool=[None]*count;i=1
    while i<count:
        tag=read('B')
        if tag==1:
            length=read('H');pool[i]=data[pos:pos+length].decode('utf-8',errors='replace');pos+=length
        elif tag in (3,4):pos+=4
        elif tag in (5,6):pos+=8;i+=1
        elif tag in (7,8,16,19,20):pool[i]=(tag,read('H'))
        elif tag in (9,10,11,12,17,18):pos+=4
        elif tag==15:pos+=3
        else:raise ValueError('Unknown constant pool tag '+str(tag))
        i+=1
    def skip_attributes():
        nonlocal pos
        for _ in range(read('H')):
            read('H');length=read('I');pos+=length
    read('H');read('H');read('H')
    for _ in range(read('H')):read('H')
    for _ in range(read('H')):
        read('H');read('H');read('H');skip_attributes()
    methods=[]
    for _ in range(read('H')):
        access=read('H');name=pool[read('H')];descriptor=pool[read('H')];skip_attributes()
        if access&1:methods.append({'name':name,'descriptor':descriptor,'access':access})
    return {'major':int.from_bytes(data[6:8],'big'),'methods':methods}

def argument_count(descriptor):
    part=descriptor.split(')',1)[0][1:];count=0;i=0
    while i<len(part):
        while part[i]=='[':i+=1
        if part[i]=='L':i=part.index(';',i)+1
        else:i+=1
        count+=1
    return count

def inventory():
    records=[];classes={}
    for filename in FILES:
        p=ROOT/'app/libs'/filename
        if not p.is_file():raise ValueError('Missing AAR '+filename)
        with zipfile.ZipFile(p) as aar:
            if aar.testzip() is not None:raise ValueError('AAR CRC failed '+filename)
            for required in ['AndroidManifest.xml','classes.jar','proguard.txt']:
                if required not in aar.namelist():raise ValueError('Incomplete AAR '+filename)
            abis=sorted({n.split('/')[1] for n in aar.namelist() if n.startswith('jni/') and n.endswith('.so')})
            with zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as jar:
                if jar.testzip() is not None:raise ValueError('JAR CRC failed '+filename)
                names=[n for n in jar.namelist() if n.endswith('.class')]
                for n in names:classes[n[:-6].replace('/','.')]=class_info(jar.read(n))
            records.append({'file':filename,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'abis':abis,'classes':len(names)})
    return records,classes

if __name__=='__main__':
    records,_=inventory()
    print(json.dumps(records,ensure_ascii=False,indent=2))
    print('Read-only archive inspection; not runtime or ABI/device compatibility verification.')
