{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MagicHash        #-}

{-# OPTIONS_HADDOCK show-extensions #-}

{-|
Copyright  :  (C) 2013-2015, University of Twente
License    :  BSD2 (see the file LICENSE)
Maintainer :  Christiaan Baaij <christiaan.baaij@gmail.com>
-}
module CLaSH.Prelude.BitReduction where

import GHC.TypeLits                   (KnownNat)

import CLaSH.Class.BitPack            (BitPack (..))
import CLaSH.Sized.Internal.BitVector (Bit, reduceAnd#, reduceOr#, reduceXor#)

-- $setup
-- >>> :set -XDataKinds
-- >>> import CLaSH.Prelude

{-# INLINE reduceAnd #-}
-- | Are all bits set to '1'?
--
-- >>> pack (-2 :: Signed 6)
-- 111110
-- >>> reduceAnd (-2 :: Signed 6)
-- 0
-- >>> pack (-1 :: Signed 6)
-- 111111
-- >>> reduceAnd (-1 :: Signed 6)
-- 1
reduceAnd :: (BitPack a, KnownNat (BitSize a)) => a -> Bit
reduceAnd v = reduceAnd# (pack v)

{-# INLINE reduceOr #-}
-- | Is there at least one bit set to '1'?
--
-- >>> pack (5 :: Signed 6)
-- 000101
-- >>> reduceOr (5 :: Signed 6)
-- 1
-- >>> pack (0 :: Signed 6)
-- 000000
-- >>> reduceOr (0 :: Signed 6)
-- 0
reduceOr :: BitPack a => a -> Bit
reduceOr v = reduceOr# (pack v)

{-# INLINE reduceXor #-}
-- | Is the number of bits set to '1' uneven?
--
-- >>> pack (5 :: Signed 6)
-- 000101
-- >>> reduceXor (5 :: Signed 6)
-- 0
-- >>> pack (28 :: Signed 6)
-- 011100
-- >>> reduceXor (28 :: Signed 6)
-- 1
-- >>> pack (-5 :: Signed 6)
-- 111011
-- >>> reduceXor (-5 :: Signed 6)
-- 1
reduceXor :: BitPack a => a -> Bit
reduceXor v = reduceXor# (pack v)
