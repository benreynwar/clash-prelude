{-# LANGUAGE DeriveDataTypeable #-}

{-# OPTIONS_HADDOCK show-extensions #-}

{-|
Copyright  :  (C) 2015, University of Twente
License    :  BSD2 (see the file LICENSE)
Maintainer :  Christiaan Baaij <christiaan.baaij@gmail.com>

The 'TopEntity' annotations described in this module make it easier to put your
design on an FPGA.

We can exert some control how the top level function is created by the CλaSH
compiler by annotating the @topEntity@ function with a 'TopEntity' annotation.
You apply these annotations using the @ANN@ pragma like so:

@
{\-\# ANN topEntity (TopEntity {t_name = ..., ...  }) \#-\}
topEntity x = ...
@

For example, given the following specification:

@
topEntity :: Signal Bit -> Signal (BitVector 8)
topEntity key1 = leds
  where
    key1R = isRising 1 key1
    leds  = mealy blinkerT (1,False,0) key1R

blinkerT (leds,mode,cntr) key1R = ((leds',mode',cntr'),leds)
  where
    -- clock frequency = 50e6   (50 MHz)
    -- led update rate = 333e-3 (every 333ms)
    cnt_max = 16650000 -- 50e6 * 333e-3

    cntr' | cntr == cnt_max = 0
          | otherwise       = cntr + 1

    mode' | key1R     = not mode
          | otherwise = mode

    leds' | cntr == 0 = if mode then complement leds
                                else rotateL leds 1
          | otherwise = leds
@

The CλaSH compiler will normally generate the following @topEntity.vhdl@ file:

@
-- Automatically generated VHDL
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use work.all;
use work.types.all;

entity topEntity is
  port(input_0         : in std_logic_vector(0 downto 0);
       -- clock
       system1000      : in std_logic;
       -- asynchronous reset: active low
       system1000_rstn : in std_logic;
       output_0        : out std_logic_vector(7 downto 0));
end;

architecture structural of topEntity is
begin
  topEntity_0_inst : entity topEntity_0
    port map
      (key1_i1         => input_0
      ,system1000      => system1000
      ,system1000_rstn => system1000_rstn
      ,topLet_o        => output_0);
end;
@

However, if we add the following 'TopEntity' annotation in the file:

@
{\-\# ANN topEntity
  ('defTop'
    { t_name     = "blinker"
    , t_inputs   = [\"KEY1\"]
    , t_outputs  = [\"LED\"]
    , t_extraIn  = [ (\"CLOCK_50\", 1)
                   , (\"KEY0\"    , 1)
                   ]
    , t_clocks   = [ 'defClkAltera' "altpll50" "CLOCK_50(0)" "not KEY0(0)" ]
    }) \#-\}
@

The CλaSH compiler will generate the following @blinker.vhdl@ file instead:

@
-- Automatically generated VHDL
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use work.all;
use work.types.all;

entity blinker is
  port(KEY1     : in std_logic_vector(0 downto 0);
       CLOCK_50 : in std_logic_vector(0 downto 0);
       KEY0     : in std_logic_vector(0 downto 0);
       LED      : out std_logic_vector(7 downto 0));
end;

architecture structural of blinker is
  signal system1000      : std_logic;
  signal system1000_rstn : std_logic;
  signal altpll50_locked : std_logic;
begin
  altpll50_inst : entity altpll50
    port map
      (inclk0 => CLOCK_50(0)
      ,c0     => system1000
      ,areset => not KEY0(0)
      ,locked => altpll50_locked);

  -- reset system1000_rstn is asynchronously asserted, but synchronously de-asserted
  resetSync_n_0 : block
    signal n_1 : std_logic;
    signal n_2 : std_logic;
  begin
    process(system1000,altpll50_locked)
    begin
      if altpll50_locked = '0' then
        n_1 <= '0';
        n_2 <= '0';
      elsif rising_edge(system1000) then
        n_1 <= '1';
        n_2 <= n_1;
      end if;
    end process;

    system1000_rstn <= n_2;
  end block;

  topEntity_0_inst : entity topEntity_0
    port map
      (key1_i1         => KEY1
      ,system1000      => system1000
      ,system1000_rstn => system1000_rstn
      ,topLet_o        => LED);
end;
@

Where we now have:

* A top-level component that is called @blinker@.
* Inputs and outputs that have a /user/-chosen name: @KEY1@, @LED@, etc.
* An instantiated <https://www.altera.com/literature/ug/ug_altpll.pdf PLL>
  component providing a stable clock signal from the free-running clock pin
  @CLOCK_50@.
* A reset that is /asynchronously/ asserted by the @lock@ signal originating from
  the PLL, meaning that your design is kept in reset until the PLL is
  providing a stable clock.
  The reset is additionally /synchronously/ de-asserted to prevent
  <http://en.wikipedia.org/wiki/Metastability_in_electronics metastability>
  of your design due to unlucky timing of the de-assertion of the reset.

See the documentation of 'TopEntity' for the meaning of all its fields.
-}
module CLaSH.Annotations.TopEntity
  ( -- * Data types
    TopEntity (..)
  , ClockSource (..)
    -- * Convenience functions
  , defTop
  , defClkAltera
  , defClkXilinx
  )
where

import Data.Data
import CLaSH.Signal.Explicit (systemClock)

-- | TopEntity annotation
data TopEntity
  = TopEntity
  { t_name     :: String         -- ^ The name the top-level component should
                                 -- have, put in a correspondingly named file.
  , t_inputs   :: [String]       -- ^ List of names that are assigned in-order
                                 -- to the inputs of the component.
  , t_outputs  :: [String]       -- ^ List of names that are assigned in-order
                                 -- to the outputs of the component.
  , t_extraIn  :: [(String,Int)]
  -- ^ Extra input ports, where every tuple holds the name of the input port and
  -- the number of  bits are used for that input port.
  --
  -- So given a bit-width @n@, the port has type:
  --
  -- @std_logic_vector (n-1 downto 0)@ in VHDL
  --
  -- and
  --
  -- @logic [n-1:0]@ in (System)Verilog.
  , t_extraOut :: [(String,Int)]
  -- ^ Extra output ports, where every tuple holds the name of the input port
  -- and the number of bits are used for that input port.
  --
  -- So given a bit-width @n@, the port has type:
  --
  -- @std_logic_vector (n-1 downto 0)@ in VHDL
  --
  -- and
  --
  -- @logic [n-1:0]@ in (System)Verilog.
  , t_clocks   :: [ClockSource]  -- ^ List of clock sources
  }
  deriving (Data,Show)

-- | A clock source
data ClockSource
  = ClockSource
  { c_name  :: String                -- ^ Component name
  , c_inp   :: Maybe (String,String) -- ^ optional: @(Input port, clock pin/expression)@
  , c_outp  :: [(String,String)]
  -- ^ List of @(Output port, clock)@
  --
  -- The best way to create the 'String' representing the name of the clock is
  -- to 'show' the corresponding singleton clock ('CLaSH.Signal.Explicit.sclock').
  --
  -- So given that you your design is synchronised to the 'CLaSH.Signal.Explicit.SystemClock'
  -- and some another clock @ClkA@
  --
  -- > type ClkA = 'Clk "clkA" 2000
  --
  -- the best way to connect output clock ports is by doing:
  --
  -- > ClockSource { ..
  -- >             , c_outp = [("c0", show (sclock :: SClock SystemClock))
  -- >                        ,("c1", show (sclock :: SClock ClkA))
  -- >                        ]
  -- >             , ..
  -- >             }
  , c_reset :: Maybe (String,String) -- ^ optional: @(Reset port, reset pin/expression)@
  , c_lock  :: String                -- ^ Output port name of the clock source
                                     -- component indicating that the clock signal
                                     -- is stable.
  , c_sync  :: Bool
  -- ^ Indicates whether the components synchronised by the clocks generated by
  -- this clock source are pulled out of reset simultaneously.
  --
  -- The recommended setting if 'False'.
  --
  -- When 'c_sync' is set to 'False', the compiler generates reset synchronisers
  -- which ensure that each component is synchronously pulled out of reset,
  -- preventing <http://en.wikipedia.org/wiki/Metastability_in_electronics metastability>
  -- introduced by unlucky timing of the reset de-assertion.
  --
  -- When 'c_sync' is set to 'True' those reset synchronisers are not generated
  -- and there is change for reset-induced metastability.
  }
  deriving (Data,Show)

-- | Default 'TopEntity' which has no clocks, and no specified names for the
-- input and output ports. Also has no clock sources:
--
-- >>> defTop
-- TopEntity {t_name = "topentity", t_inputs = [], t_outputs = [], t_extraIn = [], t_extraOut = [], t_clocks = []}
defTop :: TopEntity
defTop = TopEntity
  { t_name     = "topentity"
  , t_inputs   = []
  , t_outputs  = []
  , t_extraIn  = []
  , t_extraOut = []
  , t_clocks   = []
  }

-- | A clock source that corresponds to the Altera PLL component with default
-- settings to provide a stable 'systemClock'.
--
-- >>> defClkAltera "altpll50" "CLOCK(0)" "not KEY(0)"
-- ClockSource {c_name = "altpll50", c_inp = Just ("inclk0","CLOCK(0)"), c_outp = [("c0","system1000")], c_reset = Just ("areset","not KEY(0)"), c_lock = "locked", c_sync = False}
--
-- Will generate the following VHDL:
--
-- > altpll50_inst : entity altpll50
-- >   port map
-- >     (inclk0 => CLOCK_50(0)
-- >     ,c0     => system1000
-- >     ,areset => not KEY0(0)
-- >     ,locked => altpll50_locked);
--
-- If you are however generating (System)Verilog you should write:
--
-- >>> defClkAltera "altpll50" "CLOCK[0]" "~ KEY[0]"
-- ClockSource {c_name = "altpll50", c_inp = Just ("inclk0","CLOCK[0]"), c_outp = [("c0","system1000")], c_reset = Just ("areset","~ KEY[0]"), c_lock = "locked", c_sync = False}
--
-- so that the following (System)Verilog is created:
--
-- > altpll50 altpll50_inst
-- > (.inclk0 (CLOCK_50[0])
-- > ,.c0 (system1000)
-- > ,.areset (~ KEY0[0])
-- > ,.locked (altpll50_locked));
defClkAltera :: String -- ^ Name of the component.
             -> String -- ^ Clock Pin/Expression of the free running clock.
             -> String -- ^ Reset Pin/Expression controlling the reset of the PLL.
             -> ClockSource
defClkAltera pllName clkExpr resExpr = ClockSource
  { c_name  = pllName
  , c_inp   = Just ("inclk0",clkExpr)
  , c_outp  = [("c0",show systemClock)]
  , c_reset = Just ("areset",resExpr)
  , c_lock  = "locked"
  , c_sync  = False
  }

-- | A clock source that corresponds to the Xilinx PLL/MMCM component with
-- settings to provide a stable 'systemClock'.
--
-- >>> defClkXilinx "clkwiz50" "CLOCK(0)" "not KEY(0)"
-- ClockSource {c_name = "clkwiz50", c_inp = Just ("CLK_IN1","CLOCK(0)"), c_outp = [("CLK_OUT1","system1000")], c_reset = Just ("RESET","not KEY(0)"), c_lock = "LOCKED", c_sync = False}
--
-- Will generate the following VHDL:
--
-- > clkwiz50_inst : entity clkwiz50
-- >   port map
-- >     (CLK_IN1  => CLOCK_50(0)
-- >     ,CLK_OUT1 => system1000
-- >     ,RESET    => not KEY0(0)
-- >     ,LOCKED   => altpll50_locked);
--
-- If you are however generating (System)Verilog you should write:
--
-- >>> defClkXilinx "clkwiz50" "CLOCK[0]" "~ KEY[0]"
-- ClockSource {c_name = "clkwiz50", c_inp = Just ("CLK_IN1","CLOCK[0]"), c_outp = [("CLK_OUT1","system1000")], c_reset = Just ("RESET","~ KEY[0]"), c_lock = "LOCKED", c_sync = False}
--
-- so that the following (System)Verilog is created:
--
-- > clkwiz50 clkwiz50_inst
-- > (.CLK_IN1 (CLOCK_50[0])
-- > ,.CLK_OUT1 (system1000)
-- > ,.RESET (~ KEY0[0])
-- > ,.LOCKED (altpll50_locked));
defClkXilinx :: String -- ^ Name of the component.
             -> String -- ^ Clock Pin/Expression of the free running clock.
             -> String -- ^ Reset Pin/Expression controlling the reset of the PLL.
             -> ClockSource
defClkXilinx pllName clkExpr resExpr = ClockSource
  { c_name  = pllName
  , c_inp   = Just ("CLK_IN1",clkExpr)
  , c_outp  = [("CLK_OUT1",show systemClock)]
  , c_reset = Just ("RESET",resExpr)
  , c_lock  = "LOCKED"
  , c_sync  = False
  }
