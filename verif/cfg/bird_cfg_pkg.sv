

`ifndef BIRD_CFG_PKG_SV
`define BIRD_CFG_PKG_SV

package bird_cfg_pkg;
  parameter int BIRD_MAX_PAYLOAD_BYTES = 255;
  parameter int BIRD_MIN_PAYLOAD_BYTES = 1;
  parameter int BIRD_MAX_FRAG_NUM      = 31;
  parameter int BIRD_MAX_SEQ_NUM       = 31;
  parameter int BIRD_CRC_BYTES         = 2;
  parameter int BIRD_CLK_PERIOD_NS     = 10;
endpackage

`endif // BIRD_CFG_PKG_SV
