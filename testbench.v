`timescale 1ns/1ps

module tb_fir_16tap;

parameter N            = 16;
parameter DUT_LATENCY  = 8;    // DUT architectural pipeline stages
parameter REF_DELAY    = 6;    // Reference output pipeline depth for alignment

reg clk;
reg rst;
reg signed [15:0] x_in;
wire signed [15:0] y_out;

// VCD Dump 
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_fir_16tap);
end

//DUT 
fir_16tap dut (
    .clk(clk),
    .rst(rst),
    .x_in(x_in),
    .y_out(y_out)
);

// Clock 
always #5 clk = ~clk;

//Coefficients 
reg signed [15:0] coeff [0:N-1];
initial begin
    coeff[0]=512;  coeff[1]=1024; coeff[2]=2048; coeff[3]=4096;
    coeff[4]=8192; coeff[5]=4096; coeff[6]=2048; coeff[7]=1024;
    coeff[8]=512;  coeff[9]=256;  coeff[10]=128; coeff[11]=64;
    coeff[12]=32;  coeff[13]=16;  coeff[14]=8;   coeff[15]=4;
end

//Reference Input Register 
reg signed [15:0] x_reg_ref;

always @(posedge clk) begin
    if (rst)
        x_reg_ref <= 0;
    else
        x_reg_ref <= x_in;
end

//Reference Shift Register 
reg signed [15:0] x_hist [0:N-1];
integer i;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < N; i = i + 1)
            x_hist[i] <= 0;
    end else begin
        x_hist[0] <= x_reg_ref;
        for (i = 1; i < N; i = i + 1)
            x_hist[i] <= x_hist[i-1];
    end
end

// Pure Combinational FIR Reference 
reg signed [35:0] acc_ref;
reg signed [15:0] y_ref;

always @(*) begin
    acc_ref = 0;
    for (i = 0; i < N; i = i + 1)
        acc_ref = acc_ref + x_hist[i] * coeff[i];
end

always @(*) begin
    if ((acc_ref >>> 15) > 32767)
        y_ref = 32767;
    else if ((acc_ref >>> 15) < -32768)
        y_ref = -32768;
    else
        y_ref = acc_ref >>> 15;
end

// Reference Output Pipeline
reg signed [15:0] y_ref_pipe [0:REF_DELAY-1];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < REF_DELAY; i = i + 1)
            y_ref_pipe[i] <= 0;
    end else begin
        y_ref_pipe[0] <= y_ref;
        for (i = 1; i < REF_DELAY; i = i + 1)
            y_ref_pipe[i] <= y_ref_pipe[i-1];
    end
end

// Stimulus 
initial begin
    clk  = 0;
    rst  = 1;
    x_in = 0;

    #20 rst = 0;

    // Impulse test 
    @(posedge clk);
    x_in = 16'sd16384;   // 0.5 in Q1.15

    @(posedge clk);
    x_in = 0;

    // Random test 
    repeat (30) begin
        @(posedge clk);
        x_in = $random;
    end

    #200 $finish;
end


reg [7:0] check_delay;

always @(posedge clk) begin
    if (rst)
        check_delay <= 0;
    else if (check_delay < DUT_LATENCY + 2)
        check_delay <= check_delay + 1;
end

always @(posedge clk) begin
    if (!rst && check_delay >= DUT_LATENCY + 2) begin
        if (y_out !== y_ref_pipe[REF_DELAY-1]) begin
            $display("❌ MISMATCH @ %0t | DUT=%d REF=%d",
                     $time, y_out, y_ref_pipe[REF_DELAY-1]);
        end else begin
            $display("✅ OK @ %0t | y=%d", $time, y_out);
        end
    end
end

endmodule