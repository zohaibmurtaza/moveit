# Security & responsible use

## Intended use

MoveIt is for **education and authorized testing** — learning how synthetic input behaves on macOS, demos, and controlled experiments on machines **you own or are allowed to use**.

## Not intended for

- Misrepresenting activity to employers, clients, or schools  
- Circumventing monitoring without permission  
- Shipping as malware or an undisclosed helper  

Misuse may violate policy or law. Authors are not responsible for abusive deployments.

## Reporting vulnerabilities

If you find a security issue in MoveIt itself (e.g. unexpected privilege use, unsafe defaults):

1. Prefer a private report to the repository maintainers (GitHub Security Advisory if enabled)  
2. Include macOS version, MoveIt version (`Config/Version.xcconfig`), and steps to reproduce  

## Permissions

MoveIt requires **Accessibility** to synthesize input. It does not need Full Disk Access. Virtual HID (if ever entitled) uses Apple’s restricted HID entitlement and is optional.

## Input safeguards (1.1+)

- Character typing is **off by default** and is skipped while a text field, editor, or terminal is focused  
- App switching is limited to apps/windows the user selects — MoveIt does not drive global ⌘Tab  
- No mouse clicks; no F-keys / Escape / paging keys that commonly trigger system shortcuts
