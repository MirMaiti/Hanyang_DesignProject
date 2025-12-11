`timescale 1ns/1ps

module MainAggregator #(
    parameter int NUM_SOURCES = 10
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         in_valid,
    input  logic [NUM_SOURCES-1:0][7:0]  data_in,
    input  logic [NUM_SOURCES-1:0][1:0]  status_in,

    // NEW: additional 32-bit offsets for each SA
    input  logic [NUM_SOURCES-1:0][31:0] offset_in,

    output logic [NUM_SOURCES-1:0][31:0] diff_out,
    output logic                         done,

    output logic signed [31:0]           max_diff_value,
    output logic [$clog2(NUM_SOURCES)-1:0] max_diff_index
);

    // ------------------------
    // Status codes
    // ------------------------
    localparam STATUS_NONE   = 2'b00;
    localparam STATUS_POS    = 2'b01;
    localparam STATUS_NEG    = 2'b10;
    localparam STATUS_FINISH = 2'b11;

    // ------------------------
    // Internal state
    // ------------------------
    logic [NUM_SOURCES-1:0][31:0] pos_sum;
    logic [NUM_SOURCES-1:0][31:0] neg_sum;
    logic [5:0]                   sample_count [NUM_SOURCES-1:0];
    logic [NUM_SOURCES-1:0]       finished;

    // Extend 8-bit input to 32-bit
    function automatic logic [31:0] extend8to32(input logic [7:0] v);
        extend8to32 = {24'd0, v};
    endfunction

    // ------------------------
    // Main sequential logic
    // ------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                pos_sum[i]      <= 0;
                neg_sum[i]      <= 0;
                sample_count[i] <= 0;
                finished[i]     <= 0;
            end
            done <= 0;
        end else begin
            if (!done) begin

                if (in_valid) begin
                    for (int i = 0; i < NUM_SOURCES; i++) begin

                        if (!finished[i] && sample_count[i] < 28) begin
                            // -------------------------
                            // Handle status_in
                            // -------------------------
                            unique case (status_in[i])

                                STATUS_POS: begin
                                    pos_sum[i] <= pos_sum[i] + extend8to32(data_in[i]);
                                    sample_count[i] <= sample_count[i] + 1;
                                end

                                STATUS_NEG: begin
                                    neg_sum[i] <= neg_sum[i] + extend8to32(data_in[i]);
                                    sample_count[i] <= sample_count[i] + 1;
                                end

                                STATUS_FINISH: begin
                                    finished[i] <= 1;   // lock out future samples
                                end

                                default: ; // STATUS_NONE → ignore

                            endcase
                        end

                        // If status_in indicates FINISH, lock immediately
                        if (status_in[i] == STATUS_FINISH)
                            finished[i] <= 1;

                        // If 28 samples reached, auto-finish SA
                        if (sample_count[i] == 28)
                            finished[i] <= 1;

                    end // for loop
                end // in_valid

                // -------------------------
                // If ALL SAs are finished
                // -------------------------
                if (&finished)
                    done <= 1;

            end // if !done
        end // rst else
    end // always_ff

    // ------------------------
    // Compute final diffs
    // ------------------------
    generate
        for (genvar i = 0; i < NUM_SOURCES; i++) begin : GEN_DIFF
            assign diff_out[i] = (pos_sum[i] - neg_sum[i]) + offset_in[i];
        end
    endgenerate

    // ------------------------
    // Combinational max finder
    // ------------------------
    always_comb begin
        max_diff_value = diff_out[0];
        max_diff_index = 0;

        for (int i = 1; i < NUM_SOURCES; i++) begin
            if ($signed(diff_out[i]) > $signed(max_diff_value)) begin
                max_diff_value = diff_out[i];
                max_diff_index = i[$clog2(NUM_SOURCES)-1:0];
            end
        end
    end

endmodule
