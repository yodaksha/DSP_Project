module fir_multichannel_axis #(
    parameter N_CHANNELS = 4,            
    parameter N_TAPS = 32,               
    parameter DATA_WIDTH = 16,
    parameter COEFF_WIDTH = 16,
    parameter TID_WIDTH = $clog2(N_CHANNELS),
    parameter COEFF_ADDR_WIDTH = $clog2(N_TAPS/2)
)
(

    input  wire                          aclk,
    input  wire                          aresetn,  // Active-low reset
    
    // AXI-Stream Slave Interface (Input)
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input  wire [DATA_WIDTH-1:0]         s_axis_tdata,
    input  wire [TID_WIDTH-1:0]          s_axis_tid,     
    input  wire                          s_axis_tlast,
    
    // AXI-Stream Master Interface (Output)
    output reg                           m_axis_tvalid,
    input  wire                          m_axis_tready,
    output reg  [DATA_WIDTH-1:0]         m_axis_tdata,
    output reg  [TID_WIDTH-1:0]          m_axis_tid,
    output reg                           m_axis_tlast,
    
    // Coefficient Configuration Interface
    input  wire                          coeff_wr_en,
    input  wire [COEFF_ADDR_WIDTH-1:0]   coeff_wr_addr,
    input  wire [COEFF_WIDTH-1:0]        coeff_wr_data,
    
    // Status and Control
    input  wire                          bypass_mode,     
    output wire [N_CHANNELS-1:0]         overflow_flag,   
    output wire                          filter_busy,     
    output reg  [31:0]                   sample_count     
);


// Parameter Calculations
localparam HALF_N = N_TAPS/2;
localparam ACC_WIDTH = DATA_WIDTH + COEFF_WIDTH + $clog2(N_TAPS);
localparam LATENCY = 11;  

integer i, ch;


// Coefficient Memory
reg signed [COEFF_WIDTH-1:0] coeff_mem [0:HALF_N-1];

// Coefficients 
initial begin
    coeff_mem[0]  = 16'sd16;     
    coeff_mem[1]  = 16'sd32;     
    coeff_mem[2]  = 16'sd64;     
    coeff_mem[3]  = 16'sd128;    
    coeff_mem[4]  = 16'sd256;    
    coeff_mem[5]  = 16'sd512;    
    coeff_mem[6]  = 16'sd1024;   
    coeff_mem[7]  = 16'sd2048;   
    coeff_mem[8]  = 16'sd4096;   
    coeff_mem[9]  = 16'sd8192;   
    coeff_mem[10] = 16'sd16384;  
    coeff_mem[11] = 16'sd32767;  
    coeff_mem[12] = 16'sd32767;  
    coeff_mem[13] = 16'sd16384;  
    coeff_mem[14] = 16'sd8192;   
    coeff_mem[15] = 16'sd4096;   
end

always @(posedge aclk) begin
    if (coeff_wr_en)
        coeff_mem[coeff_wr_addr] <= coeff_wr_data;
end

// AXI-Stream Input Handshaking
reg s_ready_reg;
assign s_axis_tready = s_ready_reg;

wire input_transfer = s_axis_tvalid && s_axis_tready;

// Per-Channel Shift Registers 
reg signed [DATA_WIDTH-1:0] channel_shift [0:N_CHANNELS-1][0:N_TAPS-1];

// Current processing channel 
reg [TID_WIDTH-1:0] current_tid;
reg current_tlast;

//shift register for the active channel
always @(posedge aclk) begin
    if (!aresetn) begin
        for (ch = 0; ch < N_CHANNELS; ch = ch + 1)
            for (i = 0; i < N_TAPS; i = i + 1)
                channel_shift[ch][i] <= 0;
    end else if (input_transfer) begin
        
        channel_shift[s_axis_tid][0] <= s_axis_tdata;
        for (i = 1; i < N_TAPS; i = i + 1)
            channel_shift[s_axis_tid][i] <= channel_shift[s_axis_tid][i-1];
    end
end


always @(posedge aclk) begin
    if (!aresetn) begin
        current_tid <= 0;
        current_tlast <= 0;
    end else if (input_transfer) begin
        current_tid <= s_axis_tid;
        current_tlast <= s_axis_tlast;
    end
end


// Symmetric FIR: Pre-adders 

reg signed [DATA_WIDTH:0] pre_add [0:HALF_N-1];

always @(posedge aclk) begin
    if (!aresetn) begin
        for (i = 0; i < HALF_N; i = i + 1)
            pre_add[i] <= 0;
    end else if (input_transfer) begin
        
        for (i = 0; i < HALF_N; i = i + 1)
            pre_add[i] <= channel_shift[s_axis_tid][i] + 
                         channel_shift[s_axis_tid][N_TAPS-1-i];
    end
end

// Multiplication Stage 
reg signed [ACC_WIDTH-1:0] mult_out [0:HALF_N-1];

// Precomputed shift amounts for power-of-2 coefficients
localparam [4:0] SHIFT_0  = 4;   // 16 = 2^4
localparam [4:0] SHIFT_1  = 5;   // 32 = 2^5
localparam [4:0] SHIFT_2  = 6;   // 64 = 2^6
localparam [4:0] SHIFT_3  = 7;   // 128 = 2^7
localparam [4:0] SHIFT_4  = 8;   // 256 = 2^8
localparam [4:0] SHIFT_5  = 9;   // 512 = 2^9
localparam [4:0] SHIFT_6  = 10;  // 1024 = 2^10
localparam [4:0] SHIFT_7  = 11;  // 2048 = 2^11
localparam [4:0] SHIFT_8  = 12;  // 4096 = 2^12
localparam [4:0] SHIFT_9  = 13;  // 8192 = 2^13
localparam [4:0] SHIFT_10 = 14;  // 16384 = 2^14
localparam [4:0] SHIFT_13 = 14;  // 16384 = 2^14
localparam [4:0] SHIFT_14 = 13;  // 8192 = 2^13
localparam [4:0] SHIFT_15 = 12;  // 4096 = 2^12

localparam USE_MULT_11 = 1'b1;  // 32767
localparam USE_MULT_12 = 1'b1;  // 32767

always @(posedge aclk) begin
    if (!aresetn) begin
        for (i = 0; i < HALF_N; i = i + 1)
            mult_out[i] <= 0;
    end else if (input_transfer) begin
        // Optimized multiplication using precomputed shift amounts
        mult_out[0]  <= pre_add[0]  <<< SHIFT_0;
        mult_out[1]  <= pre_add[1]  <<< SHIFT_1;
        mult_out[2]  <= pre_add[2]  <<< SHIFT_2;
        mult_out[3]  <= pre_add[3]  <<< SHIFT_3;
        mult_out[4]  <= pre_add[4]  <<< SHIFT_4;
        mult_out[5]  <= pre_add[5]  <<< SHIFT_5;
        mult_out[6]  <= pre_add[6]  <<< SHIFT_6;
        mult_out[7]  <= pre_add[7]  <<< SHIFT_7;
        mult_out[8]  <= pre_add[8]  <<< SHIFT_8;
        mult_out[9]  <= pre_add[9]  <<< SHIFT_9;
        mult_out[10] <= pre_add[10] <<< SHIFT_10;
        mult_out[11] <= pre_add[11] * coeff_mem[11];  // 32767 requires multiplier
        mult_out[12] <= pre_add[12] * coeff_mem[12];  // 32767 requires multiplier
        mult_out[13] <= pre_add[13] <<< SHIFT_13;
        mult_out[14] <= pre_add[14] <<< SHIFT_14;
        mult_out[15] <= pre_add[15] <<< SHIFT_15;
    end
end


// Shared Adder Tree
localparam NUM_STAGES = $clog2(HALF_N);
reg signed [ACC_WIDTH-1:0] adder_tree [0:NUM_STAGES][0:HALF_N-1];

genvar stage, idx;
generate
    // Stage 0: Connect to multiplier outputs
    for (idx = 0; idx < HALF_N; idx = idx + 1) begin : stage0
        always @(posedge aclk) begin
            if (!aresetn)
                adder_tree[0][idx] <= 0;
            else if (input_transfer)
                adder_tree[0][idx] <= mult_out[idx];
        end
    end
    
    // Stages 1 to NUM_STAGES: Binary tree addition
    for (stage = 1; stage <= NUM_STAGES; stage = stage + 1) begin : stages
        localparam STAGE_SIZE = HALF_N >> stage;
        for (idx = 0; idx < STAGE_SIZE; idx = idx + 1) begin : adders
            always @(posedge aclk) begin
                if (!aresetn)
                    adder_tree[stage][idx] <= 0;
                else if (input_transfer)
                    adder_tree[stage][idx] <= adder_tree[stage-1][2*idx] + 
                                              adder_tree[stage-1][2*idx+1];
            end
        end
    end
endgenerate

wire signed [ACC_WIDTH-1:0] accumulator = adder_tree[NUM_STAGES][0];


// Scaling and Saturation 

localparam SCALE_SHIFT = COEFF_WIDTH - 1;
localparam SCALED_WIDTH = ACC_WIDTH - SCALE_SHIFT + 1;

wire signed [SCALED_WIDTH-1:0] scaled;
assign scaled = (accumulator + (1 << (SCALE_SHIFT-1))) >>> SCALE_SHIFT;

localparam signed MAX_POS = (1 << (DATA_WIDTH-1)) - 1;
localparam signed MAX_NEG = -(1 << (DATA_WIDTH-1));

reg signed [DATA_WIDTH-1:0] y_filtered;
reg [N_CHANNELS-1:0] overflow_per_channel;

always @(posedge aclk) begin
    if (!aresetn) begin
        y_filtered <= 0;
        overflow_per_channel <= 0;
    end else if (input_transfer) begin
        if (scaled > MAX_POS) begin
            y_filtered <= MAX_POS[DATA_WIDTH-1:0];
            overflow_per_channel[current_tid] <= 1;
        end else if (scaled < MAX_NEG) begin
            y_filtered <= MAX_NEG[DATA_WIDTH-1:0];
            overflow_per_channel[current_tid] <= 1;
        end else begin
            y_filtered <= scaled[DATA_WIDTH-1:0];
            overflow_per_channel[current_tid] <= 0;
        end
    end
end

assign overflow_flag = overflow_per_channel;


// Bypass Mode 

reg signed [DATA_WIDTH-1:0] bypass_data;
reg [TID_WIDTH-1:0] bypass_tid;
reg bypass_tlast;

always @(posedge aclk) begin
    if (!aresetn) begin
        bypass_data <= 0;
        bypass_tid <= 0;
        bypass_tlast <= 0;
    end else if (input_transfer) begin
        bypass_data <= s_axis_tdata;
        bypass_tid <= s_axis_tid;
        bypass_tlast <= s_axis_tlast;
    end
end


// Output Pipeline 

reg [LATENCY-1:0] valid_pipe;
reg [TID_WIDTH-1:0] tid_pipe [0:LATENCY-1];
reg tlast_pipe [0:LATENCY-1];

always @(posedge aclk) begin
    if (!aresetn) begin
        valid_pipe <= 0;
        for (i = 0; i < LATENCY; i = i + 1) begin
            tid_pipe[i] <= 0;
            tlast_pipe[i] <= 0;
        end
    end else begin
        valid_pipe <= {valid_pipe[LATENCY-2:0], input_transfer};
        tid_pipe[0] <= current_tid;
        tlast_pipe[0] <= current_tlast;
        for (i = 1; i < LATENCY; i = i + 1) begin
            tid_pipe[i] <= tid_pipe[i-1];
            tlast_pipe[i] <= tlast_pipe[i-1];
        end
    end
end


// AXI-Stream Output 

wire output_valid_internal = valid_pipe[LATENCY-1];
wire output_transfer = m_axis_tvalid && m_axis_tready;

always @(posedge aclk) begin
    if (!aresetn) begin
        m_axis_tvalid <= 0;
        m_axis_tdata <= 0;
        m_axis_tid <= 0;
        m_axis_tlast <= 0;
    end else begin
        if (output_transfer || !m_axis_tvalid) begin
            m_axis_tvalid <= output_valid_internal;
            m_axis_tdata <= bypass_mode ? bypass_data : y_filtered;
            m_axis_tid <= bypass_mode ? bypass_tid : tid_pipe[LATENCY-1];
            m_axis_tlast <= bypass_mode ? bypass_tlast : tlast_pipe[LATENCY-1];
        end
    end
end


// Backpressure Control

always @(*) begin
    if (!m_axis_tvalid || output_transfer)
        s_ready_reg = 1'b1;  
    else
        s_ready_reg = 1'b0;  
end


// Status Signals

assign filter_busy = m_axis_tvalid && !m_axis_tready;
always @(posedge aclk) begin
    if (!aresetn)
        sample_count <= 0;
    else if (input_transfer)
        sample_count <= sample_count + 1;
end

endmodule
