`timescale 1ns/1ps

module tb_MainAggregator;

    localparam int NUM_SOURCES = 10;
    localparam int N_SAMPLES   = 28;

    // DUT signals
    logic clk;
    logic rst_n;
    logic in_valid;
    logic [NUM_SOURCES-1:0][7:0]  data_in;
    logic [NUM_SOURCES-1:0][1:0]  status_in;
    logic [NUM_SOURCES-1:0][31:0] offset_in;

    logic [NUM_SOURCES-1:0][31:0] diff_out;
    logic                         done;

    logic signed [31:0]             max_diff_value;
    logic [$clog2(NUM_SOURCES)-1:0] max_diff_index;

    // Stimulus arrays
    logic [NUM_SOURCES-1:0][7:0]  din;
    logic [NUM_SOURCES-1:0][1:0]  st;

    // Expected values
    int signed pos_exp [0:NUM_SOURCES-1];
    int signed neg_exp [0:NUM_SOURCES-1];
    int signed diff_exp[0:NUM_SOURCES-1];
    int signed best_val_exp;
    int        best_idx_exp;

    // Status encoding
    localparam STATUS_NONE   = 2'b00;
    localparam STATUS_POS    = 2'b01;
    localparam STATUS_NEG    = 2'b10;
    localparam STATUS_FINISH = 2'b11;

    // DUT instance
    MainAggregator dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .data_in(data_in),
        .status_in(status_in),
        .offset_in(offset_in),
        .diff_out(diff_out),
        .done(done),
        .max_diff_value(max_diff_value),
        .max_diff_index(max_diff_index)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Send one sample cycle
    task automatic send_sample(
        input logic [NUM_SOURCES-1:0][7:0]  din_t,
        input logic [NUM_SOURCES-1:0][1:0]  st_t
    );
    begin
        @(negedge clk);
        in_valid  <= 1;
        data_in   <= din_t;
        status_in <= st_t;

        @(negedge clk);
        in_valid <= 0;

        for (int i = 0; i < NUM_SOURCES; i++) begin
            data_in[i]   <= 0;
            status_in[i] <= STATUS_NONE;
        end
    end
    endtask


    // ======================================================================
    // MAIN TEST
    // ======================================================================
    initial begin
        // Initial values
        rst_n = 0;
        in_valid = 0;

        for (int i = 0; i < NUM_SOURCES; i++) begin
            pos_exp[i] = 0;
            neg_exp[i] = 0;
            offset_in[i] = $urandom_range(0, 200);  // optional offsets
        end

        repeat(3) @(posedge clk);
        rst_n = 1;

        $display("[%0t] === RESET DONE ===", $time);

        // -----------------------------------------------------------
        // Send 28 cycles of valid inputs for each SA
        // -----------------------------------------------------------
        for (int cyc = 0; cyc < N_SAMPLES; cyc++) begin
            $display("\n===== SAMPLE %0d =====", cyc);

            for (int i = 0; i < NUM_SOURCES; i++) begin
                din[i] = $urandom_range(1,255);

                if ($urandom_range(0,1) == 0) begin
                    st[i] = STATUS_POS;
                    pos_exp[i] += din[i];
                    $display("SA%0d : +%0d", i, din[i]);
                end else begin
                    st[i] = STATUS_NEG;
                    neg_exp[i] += din[i];
                    $display("SA%0d : -%0d", i, din[i]);
                end
            end

            send_sample(din, st);
        end

        // -----------------------------------------------------------
        // After 28 cycles, send FINISH for all SAs
        // -----------------------------------------------------------
        $display("\n=== SENDING FINISH FOR ALL 10 SOURCES ===");
        for (int i = 0; i < NUM_SOURCES; i++) begin
            st[i] = STATUS_FINISH;
            din[i] = 0;
        end

        send_sample(din, st);

        // -----------------------------------------------------------
        // Wait for done
        // -----------------------------------------------------------
        wait(done == 1);
        $display("[%0t] DONE ASSERTED!", $time);

        // -----------------------------------------------------------
        // Compute expected diffs and max
        // -----------------------------------------------------------
        best_val_exp = -2147483648;
        best_idx_exp = 0;

        for (int i = 0; i < NUM_SOURCES; i++) begin
            diff_exp[i] = (pos_exp[i] - neg_exp[i]) + offset_in[i];
            if (diff_exp[i] > best_val_exp) begin
                best_val_exp = diff_exp[i];
                best_idx_exp = i;
            end
        end

        // -----------------------------------------------------------
        // Compare DUT outputs
        // -----------------------------------------------------------
        $display("\n=== CHECKING DIFF VALUES ===");
        for (int i = 0; i < NUM_SOURCES; i++) begin
            $display("SA%0d : DUT=%0d  EXP=%0d",
                     i, $signed(diff_out[i]), diff_exp[i]);

            if ($signed(diff_out[i]) !== diff_exp[i])
                $error("MISMATCH AT SA%0d!", i);
        end

        // -----------------------------------------------------------
        // Compare max index & value
        // -----------------------------------------------------------
        $display("\n=== CHECKING MAX ===");
        $display("DUT max_value = %0d, expected = %0d", 
                 $signed(max_diff_value), best_val_exp);
        $display("DUT max_index = %0d, expected = %0d",
                 max_diff_index, best_idx_exp);

        if ($signed(max_diff_value) !== best_val_exp)
            $error("MAX VALUE MISMATCH!");

        if (max_diff_index !== best_idx_exp)
            $error("MAX INDEX MISMATCH!");

        $display("\n=== TEST PASSED ===");

        #20 $finish;
    end

endmodule
