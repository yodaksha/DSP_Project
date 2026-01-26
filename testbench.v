`timescale 1ns/1ps

module tb_fir_16tap;

parameter N            = 16;
parameter DUT_LATENCY  = 9;    
parameter REF_DELAY    = 7;    

reg clk;
reg rst;
reg enable;
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
    .enable(enable),
    .x_in(x_in),
    .y_out(y_out)
);

// Clock 
always #5 clk = ~clk;

//Coefficients - Symmetric pattern
reg signed [15:0] coeff [0:N-1];
initial begin
    coeff[0]=64;   coeff[1]=128;  coeff[2]=256;  coeff[3]=512;
    coeff[4]=1024; coeff[5]=2048; coeff[6]=4096; coeff[7]=8192;
    coeff[8]=8192; coeff[9]=4096; coeff[10]=2048; coeff[11]=1024;
    coeff[12]=512; coeff[13]=256; coeff[14]=128;  coeff[15]=64;
end

// Input Register with enable
reg signed [15:0] x_reg_ref;

always @(posedge clk) begin
    if (rst)
        x_reg_ref <= 0;
    else if (enable)
        x_reg_ref <= x_in;
end

// Shift Register 
reg signed [15:0] x_hist [0:N-1];
integer i;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < N; i = i + 1)
            x_hist[i] <= 0;
    end else if (enable) begin
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
    if (((acc_ref + 36'sd16384) >>> 15) > 32767)
        y_ref = 32767;
    else if (((acc_ref + 36'sd16384) >>> 15) < -32768)
        y_ref = -32768;
    else
        y_ref = (acc_ref + 36'sd16384) >>> 15;
end

// Output Pipeline 
reg signed [15:0] y_ref_pipe [0:REF_DELAY-1];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < REF_DELAY; i = i + 1)
            y_ref_pipe[i] <= 0;
    end else if (enable) begin
        y_ref_pipe[0] <= y_ref;
        for (i = 1; i < REF_DELAY; i = i + 1)
            y_ref_pipe[i] <= y_ref_pipe[i-1];
    end
end

// Performance Counters
reg [31:0] sample_count;
reg [31:0] mismatch_count;
reg [31:0] saturation_count;
reg [31:0] test_count;

initial begin
    sample_count = 0;
    mismatch_count = 0;
    saturation_count = 0;
    test_count = 0;
end

// Count samples processed
always @(posedge clk) begin
    if (!rst && enable)
        sample_count <= sample_count + 1;
end

// Count saturation events
wire signed [20:0] scaled_monitor;
assign scaled_monitor = ((acc_ref + 36'sd16384) >>> 15);

always @(posedge clk) begin
    if (!rst && (scaled_monitor > 32767 || scaled_monitor < -32768))
        saturation_count <= saturation_count + 1;
end

// Stimulus with enhanced tests
initial begin
    clk  = 0;
    rst  = 1;
    enable = 1;
    x_in = 0;

    #20 rst = 0;
    $display("\n========== FIR FILTER VERIFICATION ==========");
    
    // Test 1: Impulse Response
    $display("\n[TEST 1] Impulse Response Test");
    test_count = test_count + 1;
    @(posedge clk);
    x_in = 16'sd16384;   // 0.5 in Q1.15
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 2: Step Response
    $display("\n[TEST 2] Step Response Test");
    test_count = test_count + 1;
    repeat (30) begin
        @(posedge clk);
        x_in = 16'sd8192;  // Constant 0.25
    end
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 3: Edge Cases - Maximum Positive
    $display("\n[TEST 3] Edge Case - Maximum Positive Input");
    test_count = test_count + 1;
    repeat (20) begin
        @(posedge clk);
        x_in = 16'sd32767;  // Max positive
    end
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 4: Edge Cases - Maximum Negative
    $display("\n[TEST 4] Edge Case - Maximum Negative Input");
    test_count = test_count + 1;
    repeat (20) begin
        @(posedge clk);
        x_in = -16'sd32768;  // Max negative
    end
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 5: Alternating Pattern
    $display("\n[TEST 5] Alternating Pattern Test");
    test_count = test_count + 1;
    repeat (20) begin
        @(posedge clk);
        x_in = 16'sd16384;
        @(posedge clk);
        x_in = -16'sd16384;
    end
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 6: Random Input
    $display("\n[TEST 6] Random Input Test");
    test_count = test_count + 1;
    repeat (50) begin
        @(posedge clk);
        x_in = $random;
    end
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 7: Clock Gating Test
    $display("\n[TEST 7] Clock Gating Test");
    test_count = test_count + 1;
    @(posedge clk);
    x_in = 16'sd10000;
    @(posedge clk);
    enable = 0;  // Disable filter
    repeat (10) begin
        @(posedge clk);
        x_in = $random;  
    end
    enable = 1; 
    @(posedge clk);
    x_in = 0;
    repeat (20) @(posedge clk);
    
    // Test 8: Zero Input Stability
    $display("\n[TEST 8] Zero Input Stability Test");
    test_count = test_count + 1;
    repeat (30) begin
        @(posedge clk);
        x_in = 0;
    end
    
    
    #100;
    $display("\n========== TEST STATISTICS ==========");
    $display("Total Tests Run:       %0d", test_count);
    $display("Total Samples:         %0d", sample_count);
    $display("Mismatches:            %0d", mismatch_count);
    $display("Saturation Events:     %0d", saturation_count);
    if (mismatch_count == 0)
        $display("\n✅ ALL TESTS PASSED!");
    else
        $display("\n❌ TESTS FAILED - %0d mismatches detected", mismatch_count);
    $display("=========================================\n");
    
    #100 $finish;
end


reg [7:0] check_delay;

always @(posedge clk) begin
    if (rst)
        check_delay <= 0;
    else if (check_delay < DUT_LATENCY + 2)
        check_delay <= check_delay + 1;
end

// Enhanced verification with mismatch tracking
always @(posedge clk) begin
    if (!rst && check_delay >= DUT_LATENCY + 2) begin
        if (y_out !== y_ref_pipe[REF_DELAY-1]) begin
            mismatch_count <= mismatch_count + 1;
            $display("❌ MISMATCH @ %0t | DUT=%d REF=%d",
                     $time, y_out, y_ref_pipe[REF_DELAY-1]);
        end else if (enable) begin  
            $display("✅ OK @ %0t | y=%d", $time, y_out);
        end
    end
end

// Assertions for runtime checking
always @(posedge clk) begin
    if (!rst && enable) begin
        
        if (y_out > 16'sd32767 || y_out < -16'sd32768) begin
            $display("⚠️  WARNING @ %0t: Output out of range: %d", $time, y_out);
        end
    end
end

endmodule