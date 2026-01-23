module fir_16tap #
(
    parameter N = 16
)
(
    input  wire              clk,
    input  wire              rst,
    input  wire signed [15:0] x_in,   // Q1.15
    output reg  signed [15:0] y_out   // Q1.15
);

integer i;

//Input Register 
reg signed [15:0] x_reg;

always @(posedge clk) begin
    if (rst)
        x_reg <= 16'sd0;
    else
        x_reg <= x_in;
end

// Shift Register 
reg signed [15:0] x_shift [0:N-1];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < N; i = i + 1)
            x_shift[i] <= 16'sd0;
    end else begin
        x_shift[0] <= x_reg;
        for (i = 1; i < N; i = i + 1)
            x_shift[i] <= x_shift[i-1];
    end
end

// Coefficients (Q1.15) 
reg signed [15:0] coeff [0:N-1];

initial begin
    coeff[0]  = 16'sd512;
    coeff[1]  = 16'sd1024;
    coeff[2]  = 16'sd2048;
    coeff[3]  = 16'sd4096;
    coeff[4]  = 16'sd8192;
    coeff[5]  = 16'sd4096;
    coeff[6]  = 16'sd2048;
    coeff[7]  = 16'sd1024;
    coeff[8]  = 16'sd512;
    coeff[9]  = 16'sd256;
    coeff[10] = 16'sd128;
    coeff[11] = 16'sd64;
    coeff[12] = 16'sd32;
    coeff[13] = 16'sd16;
    coeff[14] = 16'sd8;
    coeff[15] = 16'sd4;
end

// Multipliers 
reg signed [31:0] mult_out [0:N-1];  // Q2.30

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < N; i = i + 1)
            mult_out[i] <= 32'sd0;
    end else begin
        for (i = 0; i < N; i = i + 1)
            mult_out[i] <= x_shift[i] * coeff[i];
    end
end

// Adder Tree 
reg signed [32:0] sum1 [0:7];
reg signed [33:0] sum2 [0:3];
reg signed [34:0] sum3 [0:1];
reg signed [35:0] acc;   // Q6.30

always @(posedge clk) begin
    if (rst)
        for (i = 0; i < 8; i = i + 1) sum1[i] <= 0;
    else
        for (i = 0; i < 8; i = i + 1)
            sum1[i] <= mult_out[2*i] + mult_out[2*i+1];
end

always @(posedge clk) begin
    if (rst)
        for (i = 0; i < 4; i = i + 1) sum2[i] <= 0;
    else
        for (i = 0; i < 4; i = i + 1)
            sum2[i] <= sum1[2*i] + sum1[2*i+1];
end

always @(posedge clk) begin
    if (rst)
        for (i = 0; i < 2; i = i + 1) sum3[i] <= 0;
    else
        for (i = 0; i < 2; i = i + 1)
            sum3[i] <= sum2[2*i] + sum2[2*i+1];
end

always @(posedge clk) begin
    if (rst)
        acc <= 36'sd0;
    else
        acc <= sum3[0] + sum3[1];
end

//Scaling & Saturation (with rounding)
wire signed [20:0] scaled;
assign scaled = (acc + 36'sd16384) >>> 15;   // Q6.15, add 2^14 for rounding

always @(posedge clk) begin
    if (rst)
        y_out <= 16'sd0;
    else if (scaled > 21'sd32767)
        y_out <= 16'sd32767;
    else if (scaled < -21'sd32768)
        y_out <= -16'sd32768;
    else
        y_out <= scaled[15:0];
end

endmodule