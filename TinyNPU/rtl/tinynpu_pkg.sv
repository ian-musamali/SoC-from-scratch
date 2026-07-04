// -----------------------------------------------------------------------------
// TinyNPU global parameters (Phase 1 architecture contract).
// Single source of truth for sizing across RTL, UVM, and the golden model.
// -----------------------------------------------------------------------------
package tinynpu_pkg;

  // Input image geometry (CIFAR-style 32x32 RGB)
  parameter int IMG_WIDTH    = 32;
  parameter int IMG_HEIGHT   = 32;
  parameter int NUM_CHANNELS = 3;

  // MAC array sizing
  parameter int NUM_LANES = 64;  // parallel multiply lanes per transaction
  parameter int DATA_W    = 8;   // signed activation/weight width (int8)
  parameter int ACC_W     = 32;  // signed accumulator width (int32)

  // Classifier output classes: cat, truck, plane, ship
  parameter int NUM_CLASSES = 4;

  // ---------------------------------------------------------------------------
  // Phase 4-6: convolution engine and NPU core sizing
  // ---------------------------------------------------------------------------
  parameter int KERNEL     = 3;   // fixed 3x3 kernels
  parameter int MAX_IN_CH  = 8;   // per-layer input channel limit
  parameter int MAX_OUT_CH = 8;   // per-layer output channel limit
  parameter int MAX_LAYERS = 6;   // layer descriptor table depth
  parameter int FM_ADDR_W  = 14;  // unified int8 feature-map buffer, 16384 deep
  parameter int WGT_ADDR_W = 12;  // int8 weight memory, 4096 deep
  parameter int SHIFT_W    = 5;   // requantization shift amount width

  // Layer descriptor (67 bits packed). Field order below is MSB..LSB:
  //   img_w[66:61] img_h[60:55] in_ch[54:51] out_ch[50:47] stride2[46]
  //   pad[45] out_shift[44:40] ifm_base[39:26] ofm_base[25:12] wgt_base[11:0]
  // The Python golden model packs descriptors with the identical layout.
  typedef struct packed {
    logic [5:0]            img_w;     // input width  1..32
    logic [5:0]            img_h;     // input height 1..32
    logic [3:0]            in_ch;     // 1..MAX_IN_CH
    logic [3:0]            out_ch;    // 1..MAX_OUT_CH
    logic                  stride2;   // 0: stride 1, 1: stride 2
    logic                  pad;       // 0: no padding, 1: zero-pad by 1
    logic [SHIFT_W-1:0]    out_shift; // arithmetic >> before int8 saturation
    logic [FM_ADDR_W-1:0]  ifm_base;  // input feature map base in fm buffer
    logic [FM_ADDR_W-1:0]  ofm_base;  // output feature map base in fm buffer
    logic [WGT_ADDR_W-1:0] wgt_base;  // layer weight base in weight memory
  } layer_desc_t;

  parameter int LAYER_DESC_W = $bits(layer_desc_t);  // 67

endpackage : tinynpu_pkg
