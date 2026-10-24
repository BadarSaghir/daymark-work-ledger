# Security and privacy

Daymark stores work data locally. It does not use analytics, advertising, crash
reporting, or a remote account service.

## Reporting

Please report a suspected vulnerability privately through GitHub's **Security →
Advisories → Report a vulnerability** flow for the repository. Do not include
private ledger data in a public issue.

## Local network transfers

Nearby is an explicit, foreground-only feature. It uses unencrypted HTTP and UDP
on the local network, guarded by a rotating six-digit code. It accepts only
private, loopback, and link-local client addresses. Do not use Nearby on an
untrusted network, and do not share the transfer code with anyone you would not
hand your ledger to.

## Backups

Archives are not encrypted. Store exported ZIP files somewhere you trust. A
checksum protects against accidental corruption and casual modification; it is
not a signature and does not provide confidentiality.
