# BIRD specification notes used by the testbench

The testbench is based on the project specification, not on DUT behavior.

## Valid/ready protocol

A transfer happens only on a rising clock edge when `vld=1` and `rdy=1`. When `vld=1` and `rdy=0`, associated data/control must stay stable. The driver implements this by holding `data_in` and `cfg` until `in_rdy` is asserted.

## cfg format

- `cfg[0]`: traffic type, 0 local, 1 remote
- `cfg[7:1]`: reserved, must be 0
- `cfg[15:8]`: payload length, legal range 1 to 255
- `cfg[20:16]`: fragment number, legal range 1 to 31
- `cfg[23:21]`: reserved, must be 0
- `cfg[28:24]`: sequence number, legal range 1 to 31, 0 invalid
- `cfg[31:29]`: reserved, must be 0

## Local traffic

Local packets are single-fragment packets. The output is the payload bytes followed by the same two CRC bytes that arrived at the input. The reference model allows any non-zero `SEQ_NUM` because the spec says it has no functional impact on local routing.

## Remote traffic

Remote packets may arrive out of order. The model buffers fragments by `FRAG_NUM`, reorders them, concatenates payloads, regenerates CRC16 over the merged payload, and compares the 32-bit remote output stream.

## Silent drops

The scoreboard expects `drop_cnt` to increment once per dropped packet, not once per byte or once per invalid field. The counter is 16-bit and wraps naturally.
