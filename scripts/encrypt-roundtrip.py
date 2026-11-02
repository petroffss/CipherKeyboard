#!/usr/bin/env python3
"""Verify synthetic ciphertexts exported from the actual extension's retained host trace."""
import argparse,json,pathlib,re,subprocess
p=argparse.ArgumentParser(); p.add_argument('result',type=pathlib.Path); p.add_argument('output',type=pathlib.Path); p.add_argument('--sender-result',type=pathlib.Path); a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(a.result),'--output-path',str(a.output/'attachments')],check=True)
m=json.loads((a.output/'attachments'/'manifest.json').read_text())
if a.sender_result:
    subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(a.sender_result),'--output-path',str(a.output/'sender-attachments')],check=True)
    extra=json.loads((a.output/'sender-attachments'/'manifest.json').read_text())
    for test in extra:
        for item in test['attachments']:
            if item['suggestedHumanReadableName'].startswith('encrypt06-sender-public-key'):
                item['senderProofPath']=str(a.output/'sender-attachments'/item['exportedFileName'])
    m+=extra
records={}; sender=None
for test in m:
    for item in test['attachments']:
        name=item['suggestedHumanReadableName']; path=a.output/'attachments'/item['exportedFileName']
        if name.startswith('encrypt06-sender-public-key'): sender=pathlib.Path(item.get('senderProofPath',path)).read_text().strip()
        match=re.match(r'encrypt06-host-result-(\d+)_',name)
        if match:
            index=int(match.group(1)); text=path.read_text()
            if not text.startswith('До ckmsg1:') or not text.endswith('встречи!'): raise SystemExit('Host prefix/suffix were not preserved')
            if index in records: raise SystemExit('Duplicate cycle')
            records[index]={'ciphertext':text[3:-7],'expectedText':'a'*4096 if index==9 else 'Привет'}
if set(records)!=set(range(10)) or not sender: raise SystemExit('Missing actual ten-cycle results or trusted sender public key')
for record in records.values(): record['senderPublicKey']=sender
proof=a.output/'inserted.json'; proof.write_text(json.dumps(list(records.values()),ensure_ascii=False))
subprocess.run(['swift','run','--package-path','Packages/CipherCore','--scratch-path','.build/core','CipherInsertedProof',str(proof)],check=True)
