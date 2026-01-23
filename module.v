module fir_16tap #
(
    parameter N = 16,              // Number of taps (must be power of 2)
    parameter COEFF_WIDTH = 16,    // Coefficient bit width
    parameter DATA_WIDTH = 16      // Data bit width
)
(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,   // Clock gating for power savings
    input  wire signed [DATA_WIDTH-1:0] x_in,   // Q1.15
    output reg  signed [DATA_WIDTH-1:0] y_out   // Q1.15
);

integer i;
localparam HALF_N = N/2;
localparam ACC_WIDTH = DATA_WIDTH + COEFF_WIDTH + $clog2(N);

//Input Register with clock gating
reg signed [DATA_WIDTH-1:0] x_reg;

always @(posedge clk) begin
    if (rst)
        x_reg <= {DATA_WIDTH{1'b0}};
    else if (enable)
        x_reg <= x_in;
end

// Shift Register with clock gating
reg signed [DATA_WIDTH-1:0] x_shift [0:N-1];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < N; i = i + 1)
            x_shift[i] <= {DATA_WIDTH{1'b0}};
    end else if (enable) begin
        x_shift[0] <= x_reg;
        for (i = 1; i < N; i = i + 1)
            x_shift[i] <= x_shift[i-1];
    end
end


// Pre-adders for symmetric FIR with clock gating
reg signed [DATA_WIDTH:0] pre_add [0:HALF_N-1];  

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < HALF_N; i = i + 1)
            pre_add[i] <= {(DATA_WIDTH+1){1'b0}};
    end else if (enable) begin
        for (i = 0; i < HALF_N; i = i + 1)
            pre_add[i] <= x_shift[i] + x_shift[N-1-i];
    end
end

// Bit Shifts with clock gating 
localparam BASE_SHIFT = 6;  // For Q1.15 coefficients, base shift is 6 (2^(15-9)=64)
reg signed [ACC_WIDTH-1:0] shift_out [0:HALF_N-1];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < HALF_N; i = i + 1)
            shift_out[i] <= {ACC_WIDTH{1'b0}};
    end else if (enable) begin
        for (i = 0; i < HALF_N; i = i + 1)
            shift_out[i] <= pre_add[i] <<< (BASE_SHIFT + i);
    end
end

// Parameterized Adder Tree using generate blocks

localparam NUM_STAGES = $clog2(HALF_N);  

reg signed [ACC_WIDTH-1:0] adder_tree [0:NUM_STAGES][0:HALF_N-1];

genvar stage, idx;
generate
    // First stage: connect to shift outputs
    for (idx = 0; idx < HALF_N; idx = idx + 1) begin : first_stage_assign
        always @(posedge clk) begin
            if (rst)
                adder_tree[0][idx] <= {ACC_WIDTH{1'b0}};
            else if (enable)
                adder_tree[0][idx] <= shift_out[idx];
        end
    end
    
    // Subsequent stages: binary tree addition
    for (stage = 1; stage <= NUM_STAGES; stage = stage + 1) begin : adder_stages
        localparam STAGE_SIZE = HALF_N >> stage;  // Number of adders in this stage
        for (idx = 0; idx < STAGE_SIZE; idx = idx + 1) begin : adder_level
            always @(posedge clk) begin
                if (rst)
                    adder_tree[stage][idx] <= {ACC_WIDTH{1'b0}};
                else if (enable)
                    adder_tree[stage][idx] <= adder_tree[stage-1][2*idx] + adder_tree[stage-1][2*idx+1];
            end
        end
    end
endgenerate

// Final accumulator from last stage
wire signed [ACC_WIDTH-1:0] acc;
assign acc = adder_tree[NUM_STAGES][0];

//Scaling & Saturation (with rounding) - Parameterized
localparam SCALE_SHIFT = COEFF_WIDTH - 1;  // For Q1.15: shift by 15
localparam SCALED_WIDTH = ACC_WIDTH - SCALE_SHIFT + 1;
wire signed [SCALED_WIDTH-1:0] scaled;
assign scaled = (acc + (1 << (SCALE_SHIFT-1))) >>> SCALE_SHIFT;   // Add 2^14 for rounding

localparam MAX_POS = (1 << (DATA_WIDTH-1)) - 1;    // 32767 for 16-bit
localparam MAX_NEG = -(1 << (DATA_WIDTH-1));        // -32768 for 16-bit

always @(posedge clk) begin
    if (rst)
        y_out <= {DATA_WIDTH{1'b0}};
    else if (enable) begin
        if (scaled > MAX_POS)
            y_out <= MAX_POS[DATA_WIDTH-1:0];
        else if (scaled < MAX_NEG)
            y_out <= MAX_NEG[DATA_WIDTH-1:0];
        else
            y_out <= scaled[DATA_WIDTH-1:0];
    end
end

endmodule