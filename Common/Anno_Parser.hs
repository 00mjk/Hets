{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Christian Maeder and Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

This file implements parsers for annotations and annoted items.
   Follows Chap. II:5 of the CASL Reference Manual.

   uses Lexer, Keywords and Token rather than CaslLanguage 
-}

module Common.Anno_Parser (annotationL, annotations, 
                           parse_anno, some_id) where

import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Error
import Text.ParserCombinators.Parsec.Pos as Pos

import Common.Lexer
import Common.Token
import Common.Id as Id
import Common.AS_Annotation

comment :: GenParser Char st Annotation
comment = commentLine <|> commentGroup

some_id :: GenParser Char st Id
some_id = mixId keys keys where keys = ([], [])

charOrEof :: Char -> GenParser Char st ()
charOrEof c = (char c >> return ()) <|> eof
newlineOrEof :: GenParser Char st ()
newlineOrEof = charOrEof '\n'

commentLine :: GenParser Char st Annotation
commentLine = do 
    p <- getPos 
    try $ string "%%"
    line <- manyTill anyChar newlineOrEof
    q <- getPos
    return $ Unparsed_anno Comment_start (Line_anno line) [p, q]

dec :: Pos -> Pos
dec p = Id.incSourceColumn p (-2)

commentGroup :: GenParser Char st Annotation 
commentGroup = do 
    p <- getPos
    try $ string "%{"
    text_lines <- manyTill anyChar $ try $ string "}%"
    q <- getPos
    return $ Unparsed_anno Comment_start 
               (Group_anno $ lines text_lines) [p, dec q]

annote :: GenParser Char st Annotation
annote = anno_label <|> do 
    p <- getPos
    i <- try anno_ident
    anno <- annote_group p i <|> annote_line p i
    case parse_anno anno p of
      Left  err -> do 
        setPosition (errorPos err)
        fail (tail (showErrorMessages "or" "unknown parse error"
                    "expecting" "unexpected" "end of input"
                    (errorMessages err)))
      Right pa -> return pa

anno_label :: GenParser Char st Annotation
anno_label = do 
    p <- getPos
    try $ string "%("
    label_lines <- manyTill anyChar $ try $ string ")%"
    q <- getPos
    return (Label (lines label_lines) [p, dec q])

anno_ident :: GenParser Char st Annote_word
anno_ident = fmap Annote_word $ string "%" >> casl_words

annote_group :: Pos -> Annote_word -> GenParser Char st Annotation
annote_group p s = do 
    char '(' -- ) 
    annote_lines <- manyTill anyChar $ try $ string ")%"
    q <- getPos
    return $ Unparsed_anno s (Group_anno $ lines annote_lines) [p, dec q]

annote_line :: Pos -> Annote_word -> GenParser Char st Annotation
annote_line p s = do 
    line <- manyTill anyChar newlineOrEof
    q <- getPos
    return $ Unparsed_anno s (Line_anno line) [p, q]

annotationL :: GenParser Char st Annotation
annotationL = comment <|> annote <?> "\"%\""

annotations :: GenParser Char st [Annotation]
annotations = many (annotationL << skip) 

-----------------------------------------
-- parser for the contents of annotations
-----------------------------------------

commaIds :: GenParser Char st [Id]
commaIds = commaSep1 some_id 

parse_anno :: Annotation -> Pos -> Either ParseError Annotation
parse_anno anno sp = 
    case anno of
    Unparsed_anno (Annote_word kw) txt qs -> 
        case lookup kw $ swapTable semantic_anno_table of
        Just sa -> semantic_anno sa txt sp 
        _  -> let nsp = Id.incSourceColumn sp (length kw + 1)
                  inp = case txt of 
                        Line_anno str -> str 
                        Group_anno ls -> unlines ls
                  mkAssoc dir p = do 
                        res <- p
                        return (Assoc_anno dir res qs) in
                  case kw of
             "left_assoc"  -> parse_internal (mkAssoc ALeft commaIds) nsp inp
             "right_assoc" -> parse_internal (mkAssoc ARight commaIds) nsp inp
             "prec"     -> parse_internal (prec_anno qs)     nsp inp
             "display"  -> parse_internal (display_anno qs)  nsp inp
             "number"   -> parse_internal (number_anno qs)   nsp inp
             "string"   -> parse_internal (string_anno qs)   nsp inp
             "list"     -> parse_internal (list_anno qs)     nsp inp
             "floating" -> parse_internal (floating_anno qs) nsp inp
             _ -> Right anno
    _ -> Right anno

fromPos :: Pos -> SourcePos
fromPos p = Pos.newPos (Id.sourceName p) (Id.sourceLine p) (Id.sourceColumn p)

parse_internal :: GenParser Char () a -> Pos -> [Char] 
               -> Either ParseError a
parse_internal p sp inp = parse (do setPosition $ fromPos sp
                                    skip
                                    res <- p
                                    eof
                                    return res
                                )
                                (Id.sourceName sp)
                                inp 

checkForPlaces :: [Token] -> GenParser Char st [Token] 
checkForPlaces ts = 
    do let ps = filter isPlace ts
       if null ps then nextListToks $ topMix3 ([], [])
          -- topMix3 starts with square brackets 
          else if isSingle ps then return []
               else unexpected "multiple places"

nextListToks :: GenParser Char st [Token] -> GenParser Char st [Token]
nextListToks f = 
    do ts <- f  
       cs <- checkForPlaces ts
       return (ts ++ cs)

caslListBrackets :: GenParser Char st Id
caslListBrackets = 
    do l <- nextListToks $ afterPlace ([], [])
       (c, p) <- option ([], []) $ comps ([], [])
       return $ Id l c p

prec_anno, number_anno, string_anno, list_anno, floating_anno 
    :: [Pos] -> GenParser Char st Annotation
prec_anno ps = do 
    left_ids <- braces commaIds
    sign <- (try (string "<>") <|> (string "<")) << skip
    right_ids <- braces commaIds
    return $ Prec_anno 
               (if sign == "<" then Lower else BothDirections)
               left_ids
               right_ids
               ps 

number_anno ps = do 
    n <- some_id
    return $ Number_anno n ps

list_anno ps = do 
    bs <- caslListBrackets 
    commaT
    ni <- some_id 
    commaT
    ci <- some_id
    return $ List_anno bs ni ci ps

string_anno ps  = literal_2ids_anno ps String_anno

floating_anno ps = literal_2ids_anno ps Float_anno

literal_2ids_anno :: [Pos] -> (Id -> Id -> [Pos] -> Annotation) 
                -> GenParser Char st Annotation
literal_2ids_anno ps con = do 
    i1 <- some_id
    commaT
    i2 <- some_id
    return $ con i1 i2 ps

display_anno :: [Pos] -> GenParser Char st Annotation
display_anno ps = do 
    ident <- some_id
    tls <- many $ foldl1 (<|>) $ map disp_symb display_format_table
    return (Display_anno ident tls ps)
    where  disp_symb (df_symb, symb) = 
               do (try $ string $ "%"++symb) << skip
                  str <- manyTill anyChar $ lookAhead $ charOrEof '%'
                  return (df_symb, reverse $ dropWhile (`elem` whiteChars)
                         $ reverse str)

semantic_anno :: Semantic_anno -> Annote_text -> Pos 
              -> Either ParseError Annotation
semantic_anno sa text sp =
    let err = Left $ newErrorMessage 
              (UnExpect ("garbage after %" 
                         ++ lookupSemanticAnno sa))
              $ fromPos sp
        in case text of
                     Line_anno str ->      
                         if all (`elem` whiteChars) str then 
                            Right $ Semantic_anno sa [sp]
                         else err
                     _ -> err

