module Main where

import Text.ParserCombinators.Parsec
import qualified Common.Lib.Map as Map
import System
import System.Cmd
import Control.Monad
import Common.Utils

usage :: IO ()
usage = putStrLn 
          "Usage: it-corrections \"gen_it_characters\" \"gen_it_words\""

main :: IO ()
main = do 
  args <- getArgs
  case args of
   []        -> usage
   [_]       -> usage
   [fp1_base,fp2_base] -> do 
       let fp1 = fp1_base ++ ".txt"
           fp2 = fp2_base ++ ".txt"
           fp1_tex = fp1_base ++ ".tex"
           fp2_tex = fp2_base ++ ".tex"
           fp1_pdf = fp1_base ++ ".pdf"
           fp2_pdf = fp2_base ++ ".pdf"
       generate_tex_files fp2_tex fp1_tex
       convert_to_txt fp1_tex fp1_pdf
       convert_to_txt fp2_tex fp2_pdf
       str1 <- readFile fp1        -- file with table for every character 
       p1 <- parseItTable str1
       str2 <- readFile fp2        -- file with table for combinated characters
       p2 <- parseItTable str2
       itc <- corrections (Map.fromList (zip allCharacters p1)) 
                          (zip combinations p2) []
       str <- output itc ""  --print itc 
       putStrLn ("\nitaliccorrection_map :: Map String Int\n"++
                 "italiccorrection_map = fromList $ read " ++ post_proc str )
   _  -> usage

convert_to_txt :: FilePath -> FilePath -> IO ()
convert_to_txt tex_name pdf_name = do
  system ("pdflatex -interaction=batchmode "++tex_name++" >/dev/null") >>= 
          \ ec -> when (isFail ec) (fail "pdflatex went wrong")
  rawSystem "pdftotext" ["-raw","-q",pdf_name] >>= 
          \ ec -> when (isFail ec) (fail "pdftotext went wrong")
  return ()
  where isFail ec = case ec of
                      ExitFailure _ -> True
                      _ -> False

generate_tex_files :: String -> String -> IO ()
generate_tex_files filename1 filename2 = do
  writeFile filename1 (tex_file $ writeTexTable combinations)
  writeFile filename2 (tex_file $ writeTexTable [[c] | c <- allCharacters])

output :: [(String,Int)] -> String -> IO String
output [] str     = return (init str)
output ((s,i):xs) str = output xs $ str ++ "(\"" ++ s ++ "\"," ++ (show i) ++ ")," 
post_proc :: String -> String
post_proc str = '\"': '[': concatMap conv str ++ "]\""
    where conv c = case c of
                   '\"' -> "\\\""
                   -- converting umlauts to numbers
	           -- substitute ������� with \196\214\220\223\228\246\252
                   '�' -> "\\196"
                   '�' -> "\\214"
                   '�' -> "\\220"
                   '�' -> "\\223"
                   '�' -> "\\228"
                   '�' -> "\\246"
                   '�' -> "\\252"
                   _ -> [c]
                   

--intToString :: Int -> String
--intToString i = let (\  

---------- Parser for Table generated with "width-it-table.tex" ---------
parseItTable :: String -> IO [Double]
parseItTable str = case (parse itParser "" str) of
                    Left err -> do {putStr "parse error at"; print err;error ""}
                    Right x  -> return x
                                  

itParser :: Parser [Double]
itParser = do manyTill anyChar (try (string "wl: "))
              many1 tableEntry 
           <|> do anyChar
                  itParser
                        
                
tableEntry :: Parser Double
tableEntry = do str <- parseDouble
                string "pt"
                spaces
                (try (manyTill anyChar (try (string "wl: ")))) <|> (manyTill anyChar eof)
                return (read str)
                 
        
                     
parseDouble :: Parser String
parseDouble = many1 double

double :: Parser Char
double = digit <|> char '.'
                     
                     
stringHead :: Parser String
stringHead = do c1 <- tableChar 
                c2 <- option "" tableChar
                return (c1 ++ c2)

tableChar :: Parser String
tableChar = do str <- (try letter) <|> digit
               return [str]
--------------------------------------------------------------------------

corrections :: (Map.Map Char Double) -> [(String,Double)] -> [(String,Int)] -> IO [(String,Int)]
corrections fm []     l = return l
corrections fm (x:xs) l = corrections fm xs (l ++ [corrections' fm x])

corrections' :: (Map.Map Char Double) -> (String,Double) -> (String,Int)
corrections' fm ((c1:c2:[]),d) = let d1 = Map.findWithDefault (0.0) c1 fm
                                     d2 = Map.findWithDefault (0.0) c2 fm
                                     dif = round (((d1 + d2) - d) * 0.351 * 1000.0)
                                 in ((c1:[c2]),dif)
                                    


combinations :: [String]
combinations = let z = zipIt allCharacters allCharacters
               in [ c1:[c2] | (c1,c2) <- z ]
               where
               zipIt :: [Char] -> [Char] -> [(Char,Char)]
               zipIt []     _  = []
               zipIt (a:as) bs = (zip [a,a..] bs) ++ (zipIt as bs)

allCharacters :: [Char]
allCharacters = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++  ['�','�','�','�','�','�','�']

writeTexTable :: [String] -> String
writeTexTable []  = []
writeTexTable strl = (concat [ "\\wordline{\\textit{" ++ str ++ "}}\n\\hline\n" | str <- (fst szip) ]) 
                           ++ "\\end{tabular}\n\\newpage\n\\begin{tabular}{l|l}\n\\hline\n" 
                           ++ writeTexTable (snd szip) 
                    where
                    szip = splitAt 30 strl


tex_file :: String -> String
tex_file str = "\\documentclass[a4paper]{article}\n\\usepackage{bookman}\n\\usepackage[latin1]{inputenc}\n\\usepackage{german}\n\\usepackage{calc}\n\\usepackage{longtable}\n\\newlength{\\widthofword}\n\\setlength{\\parindent}{0cm}\n\\newcommand{\\wordline}[1]%\n{#1 & wl: \\setlength{\\widthofword}{\\widthof{#1}}\\the\\widthofword\\\\}\n\\title{Useful Widths for Typesetting-CASL}\n\\author{Klaus L�ttich}\n\\begin{document}\n\\maketitle\n\\begin{tabular}{l|l}\n\\hline\n" 
  ++ str ++ "\n\\end{tabular}\n\\end{document}"
