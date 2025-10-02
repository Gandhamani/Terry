
`timescale 1ns / 1ps
module uart_tb;

  localparam CLKS_PER_BIT = 651;
  localparam FIFO_DEPTH = 16;

  reg clk = 0;
  reg rst = 1;

  reg [7:0] tx_data;
  reg tx_dv;
  wire tx_active;
  wire tx_serial;
  wire tx_done;

  reg rx_read = 0;
  wire rx_dv;
  wire [7:0] rx_data;

  // Clock generation: 100 MHz
  always #5 clk = ~clk;

  // Instantiate UART_TX
  UARTTX #(.CLKS_PER_BIT(CLKS_PER_BIT), .FIFO_DEPTH(FIFO_DEPTH)) uart_tx (
    .i_clk(clk),
    .i_rst(rst),
    .i_TX_Byte(tx_data),
    .i_TX_DV(tx_dv),
    .o_TX_Active(tx_active),
    .o_TX_Serial(tx_serial),
    .o_TX_Done(tx_done)
  );

  // Instantiate UART_RX
  UARTRX #(.CLKS_PER_BIT(CLKS_PER_BIT), .FIFO_DEPTH(FIFO_DEPTH)) uart_rx (
    .i_clk(clk),
    .i_rst(rst),
    .i_RX_Read(rx_read),
    .i_RX_Serial(tx_serial),
    .o_RX_DV(rx_dv),
    .o_RX_Byte(rx_data)
  );

  // Test sequence
  initial begin
    $dumpfile("uart_wave.vcd");
    $dumpvars(0, uarttb);

    $display("Starting UART TX/RX Testbench...");
    rst = 1;
    tx_dv = 0;
    tx_data = 8'h00;
    #100;
    rst = 0;

    send_byte(8'hF5);
    wait_for_rx();
    send_byte(8'hDC);
    wait_for_rx();
    send_byte(8'hF0);
    wait_for_rx();
    send_byte(8'hAB);
    wait_for_rx();
    send_byte(8'h3D);
    wait_for_rx();
    send_byte(8'hF9);
    wait_for_rx();
    send_byte(8'hF2);
    wait_for_rx();
    send_byte(8'hF7);
    wait_for_rx();
    #10000;
    $finish;
  end

  // Task to send a byte
  task send_byte(input [7:0] data);
  begin
    @(posedge clk);
    tx_data = data;
    tx_dv = 1;
    @(posedge clk);
    tx_dv = 0;
    wait (tx_done);
    $display("TX Done: Sent 0x%0h at time %t", data, $time);
  end
  endtask

  // Task to wait for RX and read the byte
  task wait_for_rx;
  begin
    wait (rx_dv);
    @(posedge clk);
    rx_read <= 1;
    @(posedge clk);
    rx_read <= 0;
    $display("RX Received: 0x%0h at time %t", rx_data, $time);
  end
  endtask

endmodule
