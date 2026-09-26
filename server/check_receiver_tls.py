"""Validate the actual TLS loader, not just separately parsed public keys.

Run locally before copying a receiver certificate bundle to the NAS.
Does not print certificate/key contents or change files.
"""
import argparse
import ssl
from pathlib import Path


def validate(chain: Path, key: Path) -> None:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(chain, key)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("chain", type=Path)
    parser.add_argument("key", type=Path)
    args = parser.parse_args()
    try:
        validate(args.chain, args.key)
    except (OSError, ssl.SSLError) as error:
        parser.exit(1, f"Receiver TLS validation failed: {error}\n")
    print("PASS: receiver PEM chain and private key load together")
