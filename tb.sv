// --------------------------------------
// D Flip-Flop Interface
// --------------------------------------
interface dff_if;
  logic clk, rst;  // Clock and Reset signals
  logic d, q;      // Input D and Output Q
endinterface

// --------------------------------------
// D Flip-Flop Design Under Test (DUT)
// --------------------------------------
module dff(input logic d, clk, rst, output logic q);
  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      q <= 0;   // Reset behavior
    else
      q <= d;   // D Flip-Flop functionality
  end
endmodule

// --------------------------------------
// Transaction Class: Defines data format
// --------------------------------------
class transaction;
  bit d, rst;   // Randomized input
  bit q;        // Observed output

  // Display transaction data
  function void display(string tag);
    $display("[%s] d: %0b q: %0b rst: %0b", tag, d, q, rst);
  endfunction
endclass

// --------------------------------------
// Generator: Creates Stimulus
// --------------------------------------
class generator;
  virtual dff_if vif;
  mailbox #(transaction) gen2drv;  // To Driver
  mailbox #(transaction) gen2sb;   // To Scoreboard
  int count;                       // Number of transactions to generate

  function new(mailbox #(transaction) gen2drv, mailbox #(transaction) gen2sb);
    this.gen2drv = gen2drv;
    this.gen2sb  = gen2sb;
  endfunction

  task run();
    transaction tr;
    repeat (count) begin
      tr = new();
      tr.d = $random % 2;   // Generates 0 or 1
      tr.rst = $random % 2; // Generates 0 or 1
      gen2drv.put(tr);      // Send to Driver
      gen2sb.put(tr);       // Send to Scoreboard
      tr.display("GEN");    // Display generated transaction
    end
  endtask
endclass

// --------------------------------------
// Driver: Drives Inputs to DUT
// --------------------------------------
class driver;
  virtual dff_if vif;
  mailbox #(transaction) gen2drv;

  function new(mailbox #(transaction) gen2drv, virtual dff_if vif);
    this.gen2drv = gen2drv;
    this.vif = vif;
  endfunction

  // Apply reset sequence
  task reset();
    vif.rst <= 1;
    repeat (5) @(posedge vif.clk);
    vif.rst <= 0;
    $display("[DRV] Reset applied");
  endtask

  // Drive the DUT with input transactions
  task run();
    transaction tr;
    forever begin
      gen2drv.get(tr);      // Receive from Generator
      vif.d <= tr.d;        // Apply input
      vif.rst <= tr.rst;    // Apply reset condition
      @(posedge vif.clk);   // Wait for clock edge
    end
  endtask
endclass

// --------------------------------------
// Monitor: Observes DUT Output
// --------------------------------------
class monitor;
  virtual dff_if vif;
  mailbox #(transaction) mon2sb;  // To Scoreboard

  function new(mailbox #(transaction) mon2sb, virtual dff_if vif);
    this.mon2sb = mon2sb;
    this.vif = vif;
  endfunction

  // Monitor DUT outputs and forward to scoreboard
  task run();
    transaction tr;
    forever begin
      @(posedge vif.clk);   // Sync with clock
      #5;                   // Delay for stable output
      tr = new();
      tr.q = vif.q;
      tr.d = vif.d;
      mon2sb.put(tr);       // Send observed output
      tr.display("MON");
    end
  endtask
endclass

// --------------------------------------
// Scoreboard: Checks DUT Correctness
// --------------------------------------
class scoreboard;
  mailbox #(transaction) gen2sb;  // From Generator
  mailbox #(transaction) mon2sb; // From Monitor

  function new(mailbox #(transaction) gen2sb, mailbox #(transaction) mon2sb);
    this.gen2sb  = gen2sb;
    this.mon2sb = mon2sb;
  endfunction

  // Compare expected vs actual results
  task run();
    transaction gen_tr, mon_tr;
    forever begin
      gen2sb.get(gen_tr);    // Get expected value
      mon2sb.get(mon_tr);    // Get observed value
      gen_tr.display("SCO_GEN");
      mon_tr.display("SCO_MON");

      if (gen_tr.d === mon_tr.q || (mon_tr.q === 0 && gen_tr.rst === 1))
        $display("[SCO] Match");
      else
        $display("[SCO] Mismatch");
    end
  endtask
endclass

// --------------------------------------
// Environment: Instantiates and Runs All Components
// --------------------------------------
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;

  // Mailboxes for communication
  mailbox #(transaction) gen2drv;
  mailbox #(transaction) gen2sb;
  mailbox #(transaction) mon2sb;

  virtual dff_if vif;

  function new(virtual dff_if vif);
    this.vif = vif;

    // Create mailboxes
    gen2drv = new();
    gen2sb  = new();
    mon2sb  = new();

    // Instantiate components
    gen = new(gen2drv, gen2sb);
    drv = new(gen2drv, vif);
    mon = new(mon2sb, vif);
    sco = new(gen2sb, mon2sb);
  endfunction

  // Run the full simulation environment
  task run();
    drv.reset();  // Apply reset once at start

    fork
      gen.run();  // Generate stimulus
      drv.run();  // Drive DUT
      mon.run();  // Monitor output
      sco.run();  // Compare results
    join_none
  endtask
endclass

// --------------------------------------
// Top-Level Testbench Module
// --------------------------------------
module tb;
  dff_if vif();      // Instantiate interface
  environment env;   // Environment instance

  // Clock generation
  initial vif.clk = 0;
  always #10 vif.clk = ~vif.clk;
  
  dff dut(.d(vif.d), .q(vif.q), .clk(vif.clk), .rst(vif.rst));   // Instantiate DUT
  
  // Start the simulation
  initial begin
    env = new(vif);            // Create environment
    env.gen.count = 20;        // Set number of test cases
    env.run();                 // Start environment
  end

  // Dump waveform for EPWave
  initial begin
    $dumpfile("dump.vcd");  // Specify VCD file
    $dumpvars(0, tb);       // Dump all signals in tb module
    #500 $finish;
  end
endmodule