{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE RankNTypes #-}

module Unison.Test.Typechecker where

import           Control.Monad          (join, void)
import           Control.Monad.IO.Class (liftIO)
import           Data.Sequence          (Seq)
import           Data.Text              (unpack)
import           Data.Text.IO           (readFile)
import           EasyTest
import           System.FilePath        (joinPath, splitPath)
import           System.FilePath.Find   (always, extension, find, (==?))
import qualified Unison.Builtin         as Builtin
import           Unison.FileParsers     (Type, Term)
import           Unison.Parser          as Parser
import qualified Unison.PrettyPrintEnv  as PPE
import qualified Unison.PrintError      as PrintError
import           Unison.Result          (pattern Result, Result)
import qualified Unison.Result          as Result
import           Unison.Symbol          (Symbol)
import           Unison.Test.Common     (parseAndSynthesizeAsFile)
import qualified Unison.UnisonFile      as UF
import           Unison.Util.Monoid     (intercalateMap)
import           Control.Arrow          ((&&&))

type Note = Result.Note Symbol Parser.Ann

type SynthResult =
  Result (Seq Note) (PrintError.Env, Maybe (Term Symbol, Type Symbol))
type EitherResult = Either String (Term Symbol, Type Symbol)

ppEnv :: PPE.PrettyPrintEnv
ppEnv = PPE.fromNames Builtin.names

expectRight' :: EitherResult -> Test (Term Symbol, Type Symbol)
expectRight' (Left  e) = crash e
expectRight' (Right a) = ok >> pure a

good :: EitherResult -> Test ()
good = void <$> expectRight'

bad :: EitherResult -> Test ()
bad = void <$> EasyTest.expectLeft

test :: Test ()
test =
  scope "typechecker"
    . tests
    $ [ go shouldPassNow   good
      , go shouldFailNow   bad
      , go shouldPassLater (pending . bad)
      , go shouldFailLater (pending . good)
      ]

shouldPassPath, shouldFailPath :: String
shouldPassPath = "unison-src/tests"
shouldFailPath = "unison-src/errors"

shouldPassNow :: IO [FilePath]
shouldPassNow = find always (extension ==? ".u") shouldPassPath

shouldFailNow :: IO [FilePath]
shouldFailNow = find always (extension ==? ".u") shouldFailPath

shouldPassLater :: IO [FilePath]
shouldPassLater = find always (extension ==? ".uu") shouldPassPath

shouldFailLater :: IO [FilePath]
shouldFailLater = find always (extension ==? ".uu") shouldFailPath

go :: IO [FilePath] -> (EitherResult -> Test ()) -> Test ()
go files how = do
  files' <- liftIO files
  tests (makePassingTest how <$> files')

showNotes :: Foldable f => String -> PrintError.Env -> f Note -> String
showNotes source env notes =
  intercalateMap "\n\n" (PrintError.renderNoteAsANSI env source) notes

decodeResult
  :: String -> SynthResult -> Either String (Term Symbol, Type Symbol)
decodeResult source (Result notes Nothing) =
  Left $ showNotes source ppEnv notes
decodeResult source (Result notes (Just (env, Nothing))) =
  Left $ showNotes source env notes
decodeResult _source (Result _notes (Just (_env, Just (t, typ)))) =
  Right (t, typ)

makePassingTest :: (EitherResult -> Test ()) -> FilePath -> Test ()
makePassingTest how filepath = join $ do
  let shortName = joinPath . drop 1 . splitPath $ filepath
  source <- io $ unpack <$> Data.Text.IO.readFile filepath
  -- io $ putStrLn (show $ Builtin.names @Symbol)
  pure
    $ scope shortName
    . how
    . decodeResult source
    . fmap (fmap (fmap (UF.topLevelTerm &&& UF.typ)))
    . parseAndSynthesizeAsFile shortName
    $ source
