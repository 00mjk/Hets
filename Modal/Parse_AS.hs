{- Spickzettel f�r's Parsen 

-- Definition aus Logic.hs
type ParseFun a = FilePath -> Int -> Int -> String -> (a,String,Int,Int)
                  -- args: filename, line, column, input text
                  -- result: value, remaining text, line, column 

-- ParsecInterface.hs
toParseFun :: GenParser Char st a -> st -> ParseFun a           

-- Klassenfunktion, die meine Instanz implementiert
parse_basic_spec :: id -> Maybe(ParseFun basic_spec)
--                                       ^ R�ckgabetyp
-}

module Modal.Parse_AS where
import Common.AnnoState
import Common.Id
import Common.Token
import Common.Keywords
import Common.Lexer
import Modal.AS_Modal
import Common.AS_Annotation
-- import Data.Maybe
import Common.Lib.Parsec
--import Modal.Formula
--import CASL.SortItem
--import CASL.OpItem
--import CASL.TypeItem
import CASL.ItemList

-- aus CASL, kann bleiben
basicSpec :: AParser BASIC_SPEC
basicSpec = (fmap Basic_spec $ many1 $ 
	    try $ annoParser basicItems)
            <|> try (oBraceT >> cBraceT >> return (Basic_spec []))

basicItems :: AParser BASIC_ITEMS
basicItems = fmap Sig_items sigItems
	    <|> dotFormulae    -- sp�ter!

sigItems :: AParser SIG_ITEMS
sigItems = propItems 

propItem :: AParser PROP_ITEM 
propItem = do s <- sortId ; -- Props are the same as sorts (in declaration)
		    commaPropDecl s
		    <|> 
		    return (Prop_decl [s] [])

propItems :: AParser SIG_ITEMS
propItems = itemList propS propItem Prop_items

commaPropDecl :: Id -> AParser PROP_ITEM
commaPropDecl s = do c <- anComma
		     (is, cs) <- sortId `separatedBy` anComma
		     let l = s : is 
		         p = tokPos c : map tokPos cs in return (Prop_decl l p)


dotFormulae :: AParser BASIC_ITEMS
dotFormulae = do d <- dotT
		 (fs, ds) <- aFormula `separatedBy` dotT
		 (m, an) <- optSemi
		 let ps = map tokPos (d:ds) 
		     ns = init fs ++ [appendAnno (last fs) an]
		     in case m of 
			Nothing -> return (Axiom_items ns ps)
			Just t -> return (Axiom_items ns
			       (ps ++ [tokPos t]))

aFormula  :: AParser (Annoted FORMULA)
aFormula = bind appendAnno (annoParser formula) lineAnnos

formula :: AParser FORMULA
formula = impFormula []

impFormula :: [String] -> AParser FORMULA
impFormula k = 
             do f <- andOrFormula k
		do c <- implKey
		   (fs, ps) <- andOrFormula k `separatedBy` implKey
		   return (makeImpl (f:fs) (map tokPos (c:ps)))
		  <|>
		  do c <- ifKey
		     (fs, ps) <- andOrFormula k `separatedBy` ifKey
		     return (makeIf (f:fs) (map tokPos (c:ps)))
		  <|>
		  do c <- asKey equivS
		     g <- andOrFormula k
		     return (Equivalence f g [tokPos c])
		  <|> return f
		    where makeImpl [f,g] p = Implication f g p
		          makeImpl (f:r) (c:p) = 
			             Implication f (makeImpl r p) [c]
		          makeImpl _ _ = error "makeImpl got illegal argument"
			  makeIf l p = makeImpl (reverse l) (reverse p)

andOrFormula :: [String] -> AParser FORMULA
andOrFormula k = 
               do f <- primFormula k
		  do c <- andKey
		     (fs, ps) <- primFormula k `separatedBy` andKey
		     return (Conjunction (f:fs) (map tokPos (c:ps)))
		    <|>
		    do c <- orKey
		       (fs, ps) <- primFormula k `separatedBy` orKey
		       return (Disjunction (f:fs) (map tokPos (c:ps)))
		    <|> return f

implKey, ifKey :: AParser Token
implKey = asKey implS
ifKey = asKey ifS

instance PosItem FORMULA where
-- don't know if up_pos_l must be further defined. Now it's 'id'

updFormulaPos :: Pos -> Pos -> FORMULA -> FORMULA
updFormulaPos o c = up_pos_l (\l-> o:l++[c])

parenFormula :: [String] -> AParser FORMULA
parenFormula k = 
    do o <- oParenT
       f <- impFormula k
       c <- cParenT
       return (updFormulaPos (tokPos o) (tokPos c) f)

boxKey, diamondKey :: AParser Token
boxKey = asKey boxS
diamondKey = asKey diamondS

primFormula :: [String] -> AParser FORMULA
primFormula k = 
-- Does Modal logic operate on truth values?
-- No definedness
-- No quantification
-- No when...else
-- Diamond and Box operator
	      do c <- try(asKey notS <|> asKey negS) <?> "\"not\""
		 f <- primFormula k 
		 return (Negation f [tokPos c])
	      <|> 
	      do c <- boxKey
	         f <- primFormula k
		 return (Box f [tokPos c])
              <|> 
	      do c <- diamondKey
		 f <- primFormula k
		 return (Diamond f [tokPos c])
              <|> parenFormula k  

andKey, orKey :: AParser Token
andKey = asKey lAnd
orKey = asKey lOr







