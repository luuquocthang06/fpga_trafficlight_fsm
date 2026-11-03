`timescale 1ms/1us
// Ca 9: Loc nhieu cam bien o top-level (FILTER_MS = 50): xung 30 ms bi bo qua, xung 80 ms duoc chap nhan
module tb_c09_loc_nhieu;
    reg clk = 0; reg [2:0] sw = 3'b000;
    wire [2:0] rgb1_n, rgb2_n; wire [7:0] led_n;
    integer errors = 0;
    traffic_top #(.CLK_HZ(1000), .POR_WIDTH(3)) dut
        (.clk(clk), .key4_n(1'b1), .sw(sw), .rgb1_n(rgb1_n), .rgb2_n(rgb2_n), .led_n(led_n));
    always #0.5 clk = ~clk;
    task wait_sec(input real s); begin repeat ($rtoi(s * 1000)) @(posedge clk); #0.1; end endtask
    task check(input [2:0] a, input [2:0] b, input [511:0] name);   // {B,G,R}, 1 = sang
        begin
            if (~rgb1_n !== a || ~rgb2_n !== b) begin errors = errors + 1;
                $display("FAIL %0s: %b %b (mong doi %b %b)", name, ~rgb1_n, ~rgb2_n, a, b);
            end else $display("ok   %0s", name);
        end
    endtask
    initial begin
        wait_sec(12);  check(3'b010, 3'b001, "khoi dong xong: A xanh, B do");
        sw[1] = 1; wait_sec(0.03); sw[1] = 0; wait_sec(5);
        check(3'b010, 3'b001, "nhieu 30 ms tren TB bi bo qua: A van xanh");
        sw[1] = 1; wait_sec(0.08); sw[1] = 0; wait_sec(0.5);
        check(3'b011, 3'b001, "xe that 80 ms duoc chap nhan: A chuyen vang");
        wait_sec(6);   check(3'b001, 3'b010, "sau do B xanh, A do");
        $display("---- %0d errors ----", errors);
        if (errors == 0) $display("KET QUA: DAT"); else $display("KET QUA: KHONG DAT");
        $finish;
    end
endmodule
