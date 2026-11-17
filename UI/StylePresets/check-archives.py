#!/usr/bin/env python3
"""Exercise the production package reader with bounded adverse ZIP/control inputs."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import zipfile
import warnings

parser=argparse.ArgumentParser(description=__doc__, epilog="Example: python3 UI/StylePresets/check-archives.py --checks /path/ArchiveChecks.app/Contents/MacOS/checks --package /path/native.graphink --output /private/tmp/graphink-adverse-new")
parser.add_argument('--checks',required=True,type=Path,help='Compiled ArchiveChecks fixture executable')
parser.add_argument('--package',required=True,type=Path,help='Native emitted OPC baseline')
parser.add_argument('--output',required=True,type=Path,help='New evidence directory')
args=parser.parse_args()
if not args.checks.is_file() or not args.package.is_file(): parser.error("Fixture executable/package missing; pass existing absolute paths.")
if args.output.exists(): parser.error("Evidence exists; choose a new --output directory.")
args.output.mkdir(parents=True,exist_ok=False)
with zipfile.ZipFile(args.package) as archive:
    baseline={name:archive.read(name) for name in archive.namelist()}

def package(name,parts=None,extra=(),patch=None):
    path=args.output/(name+'.graphink')
    with warnings.catch_warnings():
        warnings.simplefilter('ignore',UserWarning)
        with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            for member,data in list((baseline if parts is None else parts).items())+list(extra):
                info=zipfile.ZipInfo(member); info.create_system=0; info.create_version=20
                info.extract_version=20; info.compress_type=zipfile.ZIP_DEFLATED
                archive.writestr(info,data)
    # Python supplies DOS archive attributes; profile emits zero.
    data=bytearray(path.read_bytes())
    end=len(data)-22; pos=struct.unpack_from('<L',data,end+16)[0]
    for _ in range(struct.unpack_from('<H',data,end+10)[0]):
        struct.pack_into('<L',data,pos+38,0)
        nl,el,cl=struct.unpack_from('<3H',data,pos+28); pos+=46+nl+el+cl
    if patch: data=patch(data)
    path.write_bytes(data)
    return path

def changed(member,old,new):
    result=dict(baseline); result[member]=result[member].replace(old.encode(),new.encode()); assert result[member]!=baseline[member]
    return result

cases=[('baseline',package('baseline'),True)]
control='graphink/document.xml'
for name,old,new in [('future-document','version="1"','version="99"'),
                     ('unknown-feature','required-features=""','required-features="future"'),
                     ('unknown-attribute','version="1"','version="1" future="true"'),
                     ('future-payload','native-graph-xml','native-graph-json'),
                     ('unknown-optional-child','</g:document>','<g:hint/></g:document>')]:
    cases.append((name,package(name,changed(control,old,new)),False))
for name,block in [
    ('future-defaults','<g:creation-defaults version="99"/>'),
    ('bad-color-archive','<g:creation-defaults version="1"><g:line-color><color archive="not-base64"/></g:line-color></g:creation-defaults>'),
    ('incomplete-rgb','<g:creation-defaults version="1"><g:line-color><color r="0.1"/></g:line-color></g:creation-defaults>'),
    ('nonfinite-color','<g:creation-defaults version="1"><g:line-color><color w="nan"/></g:line-color></g:creation-defaults>'),
    ('bad-alpha','<g:creation-defaults version="1"><g:line-color><color w="0.1" a="2"/></g:line-color></g:creation-defaults>'),
    ('qualified-color','<g:creation-defaults version="1"><g:line-color><g:color w="0.1"/></g:line-color></g:creation-defaults>'),
    ('unknown-default-field','<g:creation-defaults version="1" theme="Sketch"/>')]:
    parts=changed(control,'required-features=""','required-features="creation-defaults-v1"')
    parts[control]=parts[control].replace(b'</g:document>',(block+'</g:document>').encode())
    cases.append((name,package(name,parts),False))
for name,member,old,new in [('future-native','contents.xml','OmniGraphSketcher/v1','OmniGraphSketcher/v2'),
                           ('external-target','_rels/.rels','Target="','TargetMode="External" Target="'),
                           ('escape-target','_rels/.rels','graphink/document.xml','../../graphink/document.xml'),
                           ('percent-target','_rels/.rels','graphink/document.xml','graphink/%64ocument.xml'),
                           ('missing-graph-role','graphink/_rels/document.xml.rels','urn:graphink:relationships:graph','urn:graphink:relationships:future'),
                           ('bad-mapping','[Content_Types].xml','application/vnd.graphink.native-graph+xml','application/octet-stream')]:
    cases.append((name,package(name,changed(member,old,new)),False))
for name,extra in [('duplicate',(('contents.xml',baseline['contents.xml']),)),
                   ('equivalent',(('CONTENTS.XML',baseline['contents.xml']),)),
                   ('bad-path',(('../escape',b''),)),('optional-part',(('future.xml',b'<hint/>'),))]:
    cases.append((name,package(name,extra=extra),False))
parts=dict(baseline);parts['preview.pdf']=b'not a PDF'
parts['[Content_Types].xml']=parts['[Content_Types].xml'].replace(b'</Types>',b'<Override PartName="/preview.pdf" ContentType="application/pdf"/></Types>')
parts['graphink/_rels/document.xml.rels']=parts['graphink/_rels/document.xml.rels'].replace(b'</Relationships>',b'<Relationship Id="rPreview" Type="urn:graphink:relationships:preview" Target="../preview.pdf"/></Relationships>')
cases.append(('invalid-preview',package('invalid-preview',parts),False))
parts=dict(baseline);del parts[control];cases.append(('missing-control',package('missing-control',parts),False))
# Corrupt exact records rather than depending on library refusal alone.
def local_flags(data): struct.pack_into('<H',data,6,1); return data
def corrupt_crc(data): data[14]^=1; return data
def version10(data): struct.pack_into('<H',data,4,10);return data
def truncate(data):return data[:-1]
def corrupt_offset(data): struct.pack_into('<L',data,len(data)-6,0xffffffff);return data
for name,patch in [('encrypted',local_flags),('crc-mismatch',corrupt_crc),('deflate-version10',version10),('truncated',truncate),('zip64-offset',corrupt_offset)]:
    cases.append((name,package(name,patch=patch),False))
receipts=[]
for name,path,accepted in cases:
    result=subprocess.run([str(args.checks),'--read',str(path)],capture_output=True)
    log=result.stdout+result.stderr;(args.output/(name+'.log')).write_bytes(log)
    lines=result.stdout.decode().splitlines()
    receipt=json.loads(next(line for line in lines if line.startswith('{')))
    assert receipt['accepted']==accepted,(name,receipt)
    assert accepted or (receipt['error'] and receipt['reason']),(name,receipt)
    assert result.returncode==(0 if accepted else 2),(name,result.returncode)
    assert not any(marker in log for marker in (b'ASSERT failed',b'PRECONDITION failed',b'FAIL:')),name
    if name=='invalid-preview':
        preview=subprocess.run([str(args.checks),'--preview',str(path)],capture_output=True)
        (args.output/'invalid-preview-extraction.log').write_bytes(preview.stdout+preview.stderr)
        extracted=json.loads(next(line for line in preview.stdout.decode().splitlines() if line.startswith('{')))
        assert preview.returncode==2 and not extracted['accepted'] and extracted['reason'],extracted
    receipts.append(dict(name=name,expected_accept=accepted,**receipt))
(args.output/'verification.json').write_text(json.dumps(receipts,indent=2)+'\n')
print(f'PASS production reader: {len(cases)} baseline/adverse cases; rejected before model decode')
