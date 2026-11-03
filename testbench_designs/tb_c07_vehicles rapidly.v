`timescale 1ms/1us
// Ca 7: Xe den moi 2 s (khoang ho < GAP_SEC) - khong gap-out, bi cat o MAX_GREEN
// Chu ky clock = 1 ms  ->  1 giay mo phong = 1000 chu ky; truc thoi gian trong ModelSim doc truc tiep theo giay.
module tb_c07_xe_lien_tiep;
    localparam CK = 1000;
    localparam GRN = 2'b00, YEL = 2'b01, RED = 2'b10, OFF = 2'b11;
    localparam F = 0, S0 = 1, S1 = 2, S2 = 3, S3 = 4, S4 = 5, S5 = 6;

    reg clk = 0, reset = 1, TA = 0, TB = 0, fault = 0;
    wire [1:0] LA, LB;
    wire [2:0] state;
    traffic_ctrl #(.CLK_HZ(CK)) dut (.clk(clk), .reset(reset), .TA(TA), .TB(TB),
                                     .fault(fault), .LA(LA), .LB(LB), .state(state));
    always #0.5 clk = ~clk;

    integer errors = 0;
    real t0, d;

    task wait_sec(input real s); begin repeat ($rtoi(s * CK)) @(posedge clk); #0.1; end endtask
    task wait_state(input [2:0] s);
        integer n;
        begin
            n = 0;
            while (state !== s && n < 300 * CK) begin @(posedge clk); n = n + 1; end
            #0.1;
            if (state !== s) begin errors = errors + 1; $display("FAIL: het gio cho trang thai %0d", s); end
        end
    endtask
    // do thoi gian o trang thai s (giay): cho vao s, roi cho roi khoi s
    task measure(input [2:0] s, output real secs);
        begin
            wait_state(s); t0 = $realtime;
            while (state === s) @(posedge clk);
            #0.1; secs = ($realtime - t0) / 1000.0;
        end
    endtask
    task check_dur(input real got, input real lo, input real hi, input [511:0] name);
        begin
            if (got < lo - 0.01 || got > hi + 0.01) begin
                errors = errors + 1; $display("FAIL %0s: do duoc %0.3f s, mong doi %0.2f..%0.2f s", name, got, lo, hi);
            end else $display("ok   %0s: do duoc %0.3f s (mong doi %0.2f..%0.2f s)", name, got, lo, hi);
        end
    endtask
    task check_lights(input [2:0] es, input [1:0] ea, input [1:0] eb, input [511:0] name);
        begin
            if (state !== es || LA !== ea || LB !== eb) begin
                errors = errors + 1; $display("FAIL %0s: state=%0d LA=%b LB=%b (mong doi %0d %b %b)", name, state, LA, LB, es, ea, eb);
            end else $display("ok   %0s", name);
        end
    endtask
    task do_reset; begin reset = 1; TA = 0; TB = 0; fault = 0; wait_sec(0.005); reset = 0; end endtask
    task finish_report; begin $display("---- %0d errors ----", errors); if (errors == 0) $display("KET QUA: DAT"); else $display("KET QUA: KHONG DAT"); $finish; end endtask

    reg run_pulses = 0;
    real t_start;
    always begin wait (run_pulses); TA = 1; #200; TA = 0; #1800; end
    initial begin
        do_reset; TB = 1; wait_state(S0); t_start = $realtime;
        run_pulses = 1;
        wait_state(S1);
        d = ($realtime - t_start) / 1000.0;
        run_pulses = 0;
        check_dur(d, 20, 20, "A xanh bi cat dung o MAX_GREEN");
        finish_report;
    end
endmodule
