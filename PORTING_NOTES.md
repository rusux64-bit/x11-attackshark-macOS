# Protocol Porting Notes

| Python function | Swift function | Report ID | Length |
|---|---|---:|---:|
| `dpi_to_step` | `DPIProtocol.dpiToStep(_:)` | `0x04` | 56 |
| `step_to_dpi` | `DPIProtocol.stepToDPI(_:)` | `0x04` | 56 |
| `encode_step` | `DPIProtocol.encodeStep(_:)` | `0x04` | 56 |
| `decode_step` | `DPIProtocol.decodeStep(code:lowRange:highRange:)` | `0x04` | 56 |
| `encode_dpi` | `DPIProtocol.encode(_:)` | `0x04` | 56 |
| `decode_dpi` | `DPIProtocol.decode(_:)` | `0x04` | 56 |
