module Test.Util.Debug where

-- These flags considered only when Util.debug.tracing is true.
tracing
   :: { graphCreation :: Boolean
      , graphInputSize :: Boolean
      , graphBwdSliceInput :: Boolean
      , graphBwdSliceOutput :: Boolean
      , graphFwdSliceInput :: Boolean
      , graphFwdSliceOutput :: Boolean
      }

tracing =
   { graphCreation: false
   , graphInputSize: true
   , graphBwdSliceInput: false
   , graphBwdSliceOutput: false
   , graphFwdSliceInput: false
   , graphFwdSliceOutput: false
   }

-- Invariants that are potentially expensive to check and that we might want to disable in production,
-- that are not covered explicitly by tests.
checking
   :: { edgeListIso :: Boolean
      }

checking =
   { edgeListIso: false
   }

-- Should be set to true except when there are specific outstanding problems.
testing
   :: { fwdPreservesTop :: Boolean
      , bwdDuals :: Boolean
      , fwdDuals :: Boolean
      , naiveFwd :: Boolean
      }

testing =
   { fwdPreservesTop: true
   , bwdDuals: true
   , fwdDuals: true
   , naiveFwd: true
   }
