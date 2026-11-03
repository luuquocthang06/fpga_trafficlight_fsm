`timescale 1ms/1us
// Ca 10: Kiem thu ngau nhien (xe + che do loi) co giam sat an toan, thu tu pha va thoi gian cho toi da
module tb_c10_ngau_nhien_an_toan;
    parameter SIM_SEC = 1500;
    localparam CK = 1000;
    localparam GRN = 2'b00, YEL = 2'b01, RED = 2'b10, OFF = 2'b11;
    localparam F = 0, S0 = 1, S1 = 2, S2 = 3, S3 = 4, S4 = 5, S5 = 6;
    reg clk = 0, reset = 1, TA = 0, TB = 0, fault = 0;
    wire [1:0] LA, LB; wire [2:0] state;
    traffic_ctrl #(.CLK_HZ(CK)) dut (.clk(clk), .reset(reset), .TA(TA), .TB(TB),
                                     .fault(fault), .LA(LA), .LB(LB), .state(state));
    always #0.5 clk = ~clk;
    integer errors = 0, violations = 0, illegal = 0, k, seed = 20261030, r;
    integer normal_cnt = 0, fault_cnt = 0, waitA = 0, waitB = 0, maxwA = 0, maxwB = 0;
    reg [2:0] prev = 0;
    task wait_sec(input real s); begin repeat ($rtoi(s * CK)) @(posedge clk); #0.1; end endtask
    function normal(input [2:0] p, input [2:0] s);
        normal = (p==S0&&s==S1)||(p==S1&&s==S2)||(p==S2&&s==S3)||(p==S3&&s==S4)||
                 (p==S4&&s==S5)||(p==S5&&s==S0)||(p==F&&s==S5);
    endfunction
    // thu tu pha
    always @(posedge clk) begin
        if (reset) prev = F;
        else if (state !== prev) begin
            if (normal(prev, state)) normal_cnt = normal_cnt + 1;
            else if (state == F)     fault_cnt  = fault_cnt + 1;
            else begin illegal = illegal + 1; $display("CHUYEN TIEP SAI: %0d -> %0d", prev, state); end
            prev = state;
        end
    end
    // an toan: khong bao gio hai huong cung di
    wire a_go = (LA == GRN) || (LA == YEL), b_go = (LB == GRN) || (LB == YEL);
    always @(posedge clk) if (!reset && ((a_go && LB != RED) || (b_go && LA != RED))) begin
        violations = violations + 1; $display("VI PHAM AN TOAN t=%0t LA=%b LB=%b", $time, LA, LB);
    end
    // khong doi vo han: thoi gian cho lau nhat cua mot huong dang do co xe
    always @(posedge clk) begin
        if (reset || state == F || !dut.callA || LA != RED) waitA = 0; else waitA = waitA + 1;
        if (reset || state == F || !dut.callB || LB != RED) waitB = 0; else waitB = waitB + 1;
        if (waitA > maxwA) maxwA = waitA;
        if (waitB > maxwB) maxwB = waitB;
    end
    initial begin
        wait_sec(0.005); reset = 0;
        while ($realtime < SIM_SEC * 1000.0) begin
            r = $random(seed); TA = r[0]; TB = r[1]; fault = (r[7:4] == 0);
            r = $random(seed); wait_sec(1.0 + ((r & 32'h7FFFFFFF) % 5000) / 1000.0);
        end
        fault = 0; TA = 0; TB = 0; wait_sec(40);
        $display("     chuyen tiep binh thuong: %0d lan, vao che do loi: %0d lan", normal_cnt, fault_cnt);
        $display("     thoi gian cho do lau nhat: A %0.2f s, B %0.2f s (gioi han ly thuyet 27 s)", maxwA / 1000.0, maxwB / 1000.0);
        if (violations != 0) begin errors = errors + 1; $display("FAIL: %0d lan hai huong cung di", violations); end
        else $display("ok   an toan: khong lan nao hai huong cung di");
        if (illegal != 0) begin errors = errors + 1; $display("FAIL: %0d chuyen tiep sai thu tu", illegal); end
        else $display("ok   khong co chuyen tiep sai thu tu");
        if (maxwA > 27 * CK + 10 || maxwB > 27 * CK + 10) begin errors = errors + 1; $display("FAIL: co huong cho qua 27 s"); end
        else $display("ok   khong huong nao bi doi qua 27 s");
        $display("---- %0d errors ----", errors);
        if (errors == 0) $display("KET QUA: DAT"); else $display("KET QUA: KHONG DAT");
        $finish;
    end
endmodule
