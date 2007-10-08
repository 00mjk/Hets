{- |
Module      :  $Header$
Description :  parser for CASL (heterogeneous) structured specifications
Copyright   :  (c) Till Mossakowski, Christian Maeder, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable(Grothendieck)

Parser for CASL (heterogeneous) structured specifications
   Concerning the homogeneous syntax, this follows Sect II:3.1.3
   of the CASL Reference Manual.
-}

module Syntax.Parse_AS_Structured
    ( annoParser2
    , groupSpec
    , aSpec
    , logicName
    , parseMapping
    , translation_list
    ) where

import Logic.Logic (AnyLogic(..), language_name, data_logic, Syntax(..))
import Logic.Comorphism (targetLogic)
import Logic.Grothendieck
    ( LogicGraph (currentLogic)
    , G_basic_spec(..)
    , G_symb_map_items_list(..)
    , G_symb_items_list(..)
    , lookupLogic
    , lookupComorphism
    , AnyComorphism(..))
import Syntax.AS_Structured
import Common.AS_Annotation
import Common.AnnoState
import Common.Keywords
import Common.Lexer
import Common.Token
import Common.Id
import Text.ParserCombinators.Parsec
import Data.List((\\))

-- | parse annotations and then still call an annotation parser
annoParser2 :: AParser st (Annoted a) -> AParser st (Annoted a)
annoParser2 parser = bind (\ x (Annoted y pos l r) ->
                           Annoted y pos (x ++ l) r) annos parser

------------------------------------------------------------------------
-- logic and encoding names
------------------------------------------------------------------------

-- exclude colon (because encoding must be recognized)
-- exclude dot to recognize optional sublogic name
-- include underscore and backquote

-- better list what is allowed rather than exclude what is forbidden
-- white spaces und non-printables should be not allowed!
encodingName :: AParser st Token
encodingName = pToken(reserved (funS : casl_reserved_words) (many1
                    (oneOf ("_`" ++ (signChars \\ ":."))
                     <|> scanLPD)))

-- keep these identical in order to
-- decide after seeing ".", ":" or "->" what was meant
logicName :: AParser st Logic_name
logicName = do e <- encodingName
               do string dotS
                  s <- encodingName
                  return (Logic_name e (Just s))
                 <|> return (Logic_name e Nothing)

------------------------------------------------------------------------
-- parse Logic_code
------------------------------------------------------------------------

parseLogic :: LogicGraph -> AParser st (Logic_code, LogicGraph)
parseLogic lG = do
   lc <- parseLogicAux
   case lc of
     Logic_code _ _ (Just l) _ -> return (lc, setLogicName l lG)
     Logic_code (Just c) _ _ _ -> do
         nLg <- lookupAndSetComorphismName c lG
         return (lc, nLg)
     _ -> return (lc, lG)

parseLogicAux :: AParser st Logic_code
parseLogicAux =
    do l <- asKey logicS
       do e <- logicName -- try to parse encoding or logic source after "logic"
          case e of
              Logic_name _ (Just _) -> parseOptLogTarget Nothing (Just e) [l]
              Logic_name f Nothing ->
                      do c <- colonT
                         parseLogAfterColon (Just f) [l,c]
                      <|> parseOptLogTarget Nothing (Just e) [l]
                      <|> return (Logic_code (Just f) Nothing Nothing
                                  $ tokPos l)
         <|> do f <- asKey funS  -- parse at least a logic target after "logic"
                t <- logicName
                return $ Logic_code Nothing Nothing (Just t)
                                       $ tokPos l `appRange` tokPos f

-- parse optional logic source and target after a colon (given an encoding e)
parseLogAfterColon :: Maybe Token -> [Token] -> AParser st Logic_code
parseLogAfterColon e l =
    do s <- logicName
       parseOptLogTarget e (Just s) l
         <|> return (Logic_code e (Just s) Nothing $ catPos l)
    <|> parseOptLogTarget e Nothing l

-- parse an optional logic target (given encoding e or source s)
parseOptLogTarget :: Maybe Token -> Maybe Logic_name -> [Token]
                  -> AParser st Logic_code
parseOptLogTarget e s l =
    do f <- asKey funS
       let p = catPos $ l++[f]
       do t <- logicName
          return (Logic_code e s (Just t) p)
        <|> return (Logic_code e s Nothing p)

plainComma :: AParser st Token
plainComma = anComma `notFollowedWith` asKey logicS

------------------------------------------------------------------------
-- parse G_mapping
------------------------------------------------------------------------

callSymParser :: Maybe (AParser st a) -> String -> String ->
                 AParser st ([a], [Token])
callSymParser p name itemType = do
    case p of
         Nothing -> fail ("no symbol" ++itemType++ " parser for language "
                            ++ name)
         Just pa -> pa `separatedBy` plainComma

parseItemsMap :: AnyLogic -> AParser st (G_symb_map_items_list, [Token])
parseItemsMap (Logic lid) = do
      (cs, ps) <- callSymParser (parse_symb_map_items lid)
                  (language_name lid) " maps"
      return (G_symb_map_items_list lid cs, ps)


parseMapping :: LogicGraph -> AParser st ([G_mapping], [Token])
parseMapping = parseMapOrHide G_logic_translation G_symb_map parseItemsMap

parseMapOrHide :: (Logic_code -> a) -> (t -> a)
               -> (AnyLogic -> AParser st (t, [Token])) -> LogicGraph
               -> AParser st ([a], [Token])
parseMapOrHide constrLogic constrMap pa lG =
    do (n, nLg) <- parseLogic lG
       do c <- anComma
          (gs, ps) <- parseMapOrHide constrLogic constrMap pa nLg
          return (constrLogic n : gs, c:ps)
        <|> return ([constrLogic n], [])
    <|> do l <- lookupLogic "parseMapOrHide" (currentLogic lG) lG
           (m, ps) <- pa l
           do  c <- anComma
               (gs, qs) <- parseMapOrHide constrLogic constrMap pa lG
               return (constrMap m : gs, ps ++ c : qs)
             <|> return ([constrMap m], ps)

------------------------------------------------------------------------
-- parse G_hiding
------------------------------------------------------------------------

parseItemsList :: AnyLogic -> AParser st (G_symb_items_list, [Token])
parseItemsList (Logic lid) = do
      (cs, ps) <- callSymParser (parse_symb_items lid)
                  (language_name lid) ""
      return (G_symb_items_list lid cs, ps)

parseHiding :: LogicGraph -> AParser st ([G_hiding], [Token])
parseHiding = parseMapOrHide G_logic_projection G_symb_list parseItemsList

------------------------------------------------------------------------
-- specs
------------------------------------------------------------------------

spec :: LogicGraph -> AParser st (Annoted SPEC)
spec l = do (sps,ps) <- annoParser2 (specA l) `separatedBy` (asKey thenS)
            return $ case sps of
                    [sp] -> sp
                    _ -> emptyAnno (Extension sps $ catPos ps)

specA :: LogicGraph -> AParser st (Annoted SPEC)
specA l = do (sps,ps) <- annoParser2 (specB l) `separatedBy` (asKey andS)
             return $ case sps of
                     [sp] -> sp
                     _ -> emptyAnno (Union sps $ catPos ps)

specB :: LogicGraph -> AParser st (Annoted SPEC)
specB l = do    p1 <- asKey localS
                sp1 <- aSpec l
                p2 <- asKey withinS
                sp2 <- annoParser2 $ specB l
                return (emptyAnno $ Local_spec sp1 sp2
                                  $ tokPos p1 `appRange` tokPos p2)
          <|> specC l

specC :: LogicGraph -> AParser st (Annoted SPEC)
specC lG = do
    let spD = annoParser $ specD lG
        rest = spD >>= translation_list lG Translation Reduction
    l@(Logic lid) <- lookupLogic "specC" (currentLogic lG) lG
    case data_logic lid of
          Nothing -> rest
          Just lD@(Logic dl) -> do
              p1 <- asKey dataS -- not a keyword
              sp1 <- annoParser $ basicSpec lD
                  <|> groupSpec lG { currentLogic = language_name dl }
              sp2 <- spD
              return (emptyAnno $ Data lD l sp1 sp2 $ tokPos p1)
            <|> rest

translation_list :: LogicGraph -> (Annoted b -> RENAMING -> b)
                 -> (Annoted b -> RESTRICTION -> b) -> Annoted b
                 -> AParser st (Annoted b)
translation_list l ftrans frestr sp =
     do sp' <- translation l sp ftrans frestr
        translation_list l ftrans frestr (emptyAnno sp')
 <|> return sp

-- | Parse renaming
-- @
-- RENAMING ::= with SYMB-MAP-ITEMS-LIST
-- @
-- SYMB-MAP-ITEMS-LIST is parsed using parseMapping
renaming :: LogicGraph -> AParser st RENAMING
renaming l =
    do kWith <- asKey withS
       (mappings, commas) <- parseMapping l
       return (Renaming mappings $ catPos $ kWith:commas)

-- | Parse restriction
-- @
-- RESTRICTION ::= hide SYMB-ITEMS-LIST
--               | reveal SYMB-MAP-ITEMS-LIST
-- @
-- SYMB-ITEMS-LIST is parsed using parseHiding; SYMB-MAP-ITEMS-LIST is
-- parsed using parseItemsMap
restriction :: LogicGraph -> AParser st RESTRICTION
restriction l =
        -- hide
    do kHide <- asKey hideS
       (symbs, commas) <- parseHiding l
       return (Hidden symbs (catPos (kHide : commas)))
    <|> -- reveal
    do kReveal <- asKey revealS
       nl <- lookupLogic "reveal" (currentLogic l) l
       (mappings, commas) <- parseItemsMap nl
       return (Revealed mappings (catPos (kReveal : commas)))

translation :: LogicGraph -> a -> (a -> RENAMING -> b)
            -> (a -> RESTRICTION -> b) -> AParser st b
translation l sp ftrans frestr =
    do r <- renaming l
       return (ftrans sp r)
    <|>
    do r <- restriction l
       return (frestr sp r)

groupSpecLookhead :: AParser st Token
groupSpecLookhead = oBraceT <|> ((simpleId << annos)
                                 `followedWith`
                                 (asKey withS <|> asKey hideS
                                  <|> asKey revealS <|> asKey andS
                                  <|> asKey thenS <|> cBraceT
                                  <|> asKey fitS <|> asKey viewS
                                  <|> asKey specS <|> asKey archS
                                  <|> asKey unitS
                                  <|> asKey withinS <|> asKey endS
                                  <|> oBracketT <|> cBracketT
                                  <|> (eof >> return (Token "" nullRange))))

specD :: LogicGraph -> AParser st SPEC
           -- do some lookahead for free spec, to avoid clash with free type
specD l = do p <- asKey freeS `followedWith` groupSpecLookhead
             sp <- annoParser $ groupSpec l
             return (Free_spec sp $ tokPos p)
      <|> do p <- asKey cofreeS `followedWith` groupSpecLookhead
             sp <- annoParser $ groupSpec l
             return (Cofree_spec sp $ tokPos p)
      <|> do p <- asKey closedS `followedWith` groupSpecLookhead
             sp <- annoParser $ groupSpec l
             return (Closed_spec sp $ tokPos p)
      <|> specE l

specE :: LogicGraph -> AParser st SPEC
specE l = logicSpec l
      <|> (lookAhead groupSpecLookhead >> groupSpec l)
      <|> do
        nl <- lookupLogic "basic spec" (currentLogic l) l
        basicSpec nl

-- | call a logic specific parser if it exists
callParser :: Maybe (AParser st a) -> String -> String -> AParser st a
callParser p name itemType = do
    case p of
         Nothing -> fail ("no "++itemType++" parser for language "
                            ++ name)
         Just pa -> pa

basicSpec :: AnyLogic -> AParser st SPEC
basicSpec (Logic lid) = do
    p <- getPos
    bspec <- callParser (parse_basic_spec lid) (language_name lid)
             "basic specification"
    q <- getPos
    return $ Basic_spec (G_basic_spec lid bspec) $ Range [p, q]

logicSpec :: LogicGraph -> AParser st SPEC
logicSpec lG = do
   s1 <- asKey logicS
   ln <- logicName
   s2 <- colonT
   sp <- annoParser $ specD $ setLogicName ln lG
   return $ Qualified_spec ln sp $ toPos s1 [] s2

setLogicName :: Logic_name -> LogicGraph -> LogicGraph
setLogicName (Logic_name lid _) lg = lg { currentLogic = tokStr lid }

lookupAndSetComorphismName :: Token -> LogicGraph -> AParser st LogicGraph
lookupAndSetComorphismName ctok lg = do
    Comorphism cid <- lookupComorphism (tokStr ctok) lg
    return lg { currentLogic = language_name $ targetLogic cid }

aSpec :: LogicGraph -> AParser st (Annoted SPEC)
aSpec l = annoParser2 (spec l)

groupSpec :: LogicGraph -> AParser st SPEC
groupSpec l = do
    b <- oBraceT
    do
      c <- cBraceT
      return $ EmptySpec $ catPos [b, c]
     <|> do
      a <- aSpec l
      c <- cBraceT
      return $ Group a $ catPos [b, c]
  <|> do
    n <- simpleId
    (f, ps) <- fitArgs l
    return (Spec_inst n f ps)

fitArgs :: LogicGraph -> AParser st ([Annoted FIT_ARG],Range)
fitArgs l = do fas <- many (fitArg l)
               let (fas1,ps) = unzip fas
               return (fas1,concatMapRange id ps)

fitArg :: LogicGraph -> AParser st (Annoted FIT_ARG,Range)
fitArg l = do b <- oBracketT
              fa <- annoParser (fittingArg l)
              c <- cBracketT
              return (fa, toPos b [] c)

fittingArg :: LogicGraph -> AParser st FIT_ARG
fittingArg l = do s <- asKey viewS
                  vn <- simpleId
                  (fa,ps) <- fitArgs l
                  return (Fit_view vn fa (tokPos s`appRange` ps))
            <|>
               do sp <- aSpec l
                  (symbit, ps) <- option ([],nullRange) $ do
                                 s <- asKey fitS
                                 (m, qs) <- parseMapping l
                                 return (m, catPos $ s : qs)
                  return (Fit_spec sp symbit ps)
