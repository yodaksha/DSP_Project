`timescale 1ns/1ps

module tb_fir_file_input;

parameter N_CHANNELS = 4;
parameter N_TAPS = 32;  // 32-tap filter
parameter DATA_WIDTH = 16;
parameter COEFF_WIDTH = 16;
parameter TID_WIDTH = $clog2(N_CHANNELS);

// Clock and Reset
reg aclk;
reg aresetn;

// AXI-Stream Slave (Input)
reg s_axis_tvalid;
wire s_axis_tready;
reg [DATA_WIDTH-1:0] s_axis_tdata;
reg [TID_WIDTH-1:0] s_axis_tid;
reg s_axis_tlast;

// AXI-Stream Master (Output)
wire m_axis_tvalid;
reg m_axis_tready;
wire [DATA_WIDTH-1:0] m_axis_tdata;
wire [TID_WIDTH-1:0] m_axis_tid;
wire m_axis_tlast;

// Coefficient Configuration
reg coeff_wr_en;
reg [$clog2(N_TAPS/2)-1:0] coeff_wr_addr;
reg [COEFF_WIDTH-1:0] coeff_wr_data;

// Status
reg bypass_mode;
wire [N_CHANNELS-1:0] overflow_flag;
wire filter_busy;
wire [31:0] sample_count;

// DUT Instantiation
fir_multichannel_axis #(
    .N_CHANNELS(N_CHANNELS),
    .N_TAPS(N_TAPS),
    .DATA_WIDTH(DATA_WIDTH),
    .COEFF_WIDTH(COEFF_WIDTH)
) dut (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tid(s_axis_tid),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tid(m_axis_tid),
    .m_axis_tlast(m_axis_tlast),
    .coeff_wr_en(coeff_wr_en),
    .coeff_wr_addr(coeff_wr_addr),
    .coeff_wr_data(coeff_wr_data),
    .bypass_mode(bypass_mode),
    .overflow_flag(overflow_flag),
    .filter_busy(filter_busy),
    .sample_count(sample_count)
);

// Clock generation (10ns period = 100MHz)
always #5 aclk = ~aclk;

// File handling
integer input_file, output_file;
integer input_value, ref_value;
integer ref_file, scan_result;
integer sample_index;
integer mismatch_count;
integer total_samples;

// Output monitoring
reg signed [DATA_WIDTH-1:0] captured_output;
reg output_captured;

// Capture output when valid
always @(posedge aclk) begin
    if (m_axis_tvalid && m_axis_tready) begin
        captured_output <= m_axis_tdata;
        output_captured <= 1;
    end else begin
        output_captured <= 0;
    end
end

// Main test
initial begin
    // VCD dump
    $dumpfile("file_input_test.vcd");
    $dumpvars(0, tb_fir_file_input);
    
    // Initialize
    aclk = 0;
    aresetn = 0;
    s_axis_tvalid = 0;
    s_axis_tdata = 0;
    s_axis_tid = 0;
    s_axis_tlast = 0;
    m_axis_tready = 1;
    coeff_wr_en = 0;
    bypass_mode = 0;
    sample_index = 0;
    mismatch_count = 0;
    total_samples = 0;
    
    // Open files
    input_file = $fopen("input32.txt", "r");
    output_file = $fopen("output_actual.txt", "w");
    
    if (input_file == 0) begin
        $display("ERROR: Cannot open input32.txt");
        $finish;
    end
    
    // Wait for reference values to be loaded
    #1;
    
    $display("========================================");
    $display("File-Based FIR Filter Test");
    $display("========================================");
    $display("Input: input32.txt");
    $display("Reference: output_ref32.txt");
    $display("========================================\n");
    
    // Reset
    #20 aresetn = 1;
    #10;
    
    // Process input samples
    while (!$feof(input_file)) begin
        scan_result = $fscanf(input_file, "%d\n", input_value);
        if (scan_result == 1) begin
            // Send input sample
            @(posedge aclk);
            s_axis_tvalid = 1;
            s_axis_tdata = input_value;
            s_axis_tid = 0;  // Use channel 0
            s_axis_tlast = 0;
            
            // Wait for handshake
            while (!s_axis_tready) @(posedge aclk);
            
            @(posedge aclk);
            s_axis_tvalid = 0;
            
            sample_index = sample_index + 1;
        end
    end
    
    // Wait for pipeline to flush (LATENCY = 9 cycles)
    repeat(20) @(posedge aclk);
    
    $fclose(input_file);
    $fclose(output_file);
    
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total input samples:  %0d", sample_index);
    $display("Total output samples: %0d", total_samples);
    $display("Mismatches:           %0d", mismatch_count);
    if (mismatch_count == 0)
        $display("Status: PASS ✓");
    else
        $display("Status: FAIL ✗");
    $display("========================================\n");
    
    $finish;
end

// Pre-load all reference values
integer ref_values[0:499];
integer ref_count;

initial begin
    ref_count = 0;
    ref_file = $fopen("output_ref32.txt", "r");
    if (ref_file != 0) begin
        while (!$feof(ref_file) && ref_count < 500) begin
            scan_result = $fscanf(ref_file, "%d\n", ref_value);
            if (scan_result == 1) begin
                ref_values[ref_count] = ref_value;
                ref_count = ref_count + 1;
            end
        end
        $fclose(ref_file);
    end
end

// Compare outputs with reference - account for pipeline fill
localparam PIPELINE_FILL = 3;  // Pipeline delay

always @(posedge aclk) begin
    if (m_axis_tvalid && m_axis_tready) begin
        // Write actual output
        $fwrite(output_file, "%d\n", $signed(m_axis_tdata));
        
        // Skip first PIPELINE_FILL outputs, then start comparing
        if (total_samples >= PIPELINE_FILL && (total_samples - PIPELINE_FILL) < ref_count) begin
            // Compare with reference
            if ($signed(m_axis_tdata) !== ref_values[total_samples - PIPELINE_FILL]) begin
                mismatch_count = mismatch_count + 1;
                if (mismatch_count <= 10) begin  // Show first 10 mismatches
                    $display("[MISMATCH %0d] Sample %0d: Expected %0d, Got %0d, Diff = %0d",
                            mismatch_count, total_samples + 1, 
                            ref_values[total_samples - PIPELINE_FILL], $signed(m_axis_tdata), 
                            ref_values[total_samples - PIPELINE_FILL] - $signed(m_axis_tdata));
                end
            end else if ((total_samples - PIPELINE_FILL) <= 10 || total_samples % 50 == 0) begin
                $display("[MATCH] Sample %0d: %0d ✓", total_samples + 1, $signed(m_axis_tdata));
            end
        end
        
        total_samples = total_samples + 1;
    end
end

endmodule
