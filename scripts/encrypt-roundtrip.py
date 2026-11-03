#!/usr/bin/env python3
"""Verify synthetic ciphertexts exported from the actual extension's retained host trace."""
import argparse,base64,binascii,json,pathlib,re,subprocess

HOST_PREFIX = "До "
HOST_SUFFIX = "встречи!"


def extract_host_ciphertext(text: str) -> str:
    """Require the exact retained host framing and a canonical one-line output token."""
    if not text.startswith(HOST_PREFIX) or not text.endswith(HOST_SUFFIX):
        raise ValueError("Host prefix/suffix were not preserved")
    ciphertext = text[len(HOST_PREFIX):len(text) - len(HOST_SUFFIX)]
    match = re.fullmatch(r"ckmsg2:([A-Za-z0-9_-]+)", ciphertext)
    if match is None:
        raise ValueError("Host insertion is not a single canonical ckmsg2 string")
    body = match.group(1)
    try:
        decoded = base64.b64decode(body + "=" * (-len(body) % 4), altchars=b"-_", validate=True)
    except binascii.Error as error:
        raise ValueError("Host insertion has invalid base64url") from error
    if base64.urlsafe_b64encode(decoded).decode("ascii").rstrip("=") != body:
        raise ValueError("Host insertion has noncanonical base64url")
    return ciphertext


def main():
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
                try:
                    ciphertext=extract_host_ciphertext(text)
                except ValueError as error:
                    raise SystemExit(f'Cycle {index}: {error}') from error
                if index in records: raise SystemExit('Duplicate cycle')
                records[index]={'ciphertext':ciphertext,'expectedText':'a'*4096 if index==9 else 'Привет'}
    if set(records)!=set(range(10)) or not sender: raise SystemExit('Missing actual ten-cycle results or trusted sender public key')
    for record in records.values(): record['senderPublicKey']=sender
    proof=a.output/'inserted.json'; proof.write_text(json.dumps(list(records.values()),ensure_ascii=False))
    subprocess.run(['swift','run','--package-path','Packages/CipherCore','--scratch-path','.build/core','CipherInsertedProof',str(proof)],check=True)


if __name__ == "__main__":
    main()
