{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms #-}

module Syntax (TyVar, TmVar, Typ (..), PrimOp (..), opTyp, Trm (..), pattern TAll, pattern TLam) where

import Data.Data (Typeable)
import GHC.Generics (Generic)
import Unbound.Generics.LocallyNameless

type TyVar = Name Typ

type TmVar = Name Trm

data Typ
  = TInt
  | TBool
  | TTop
  | TBot
  | TVar TyVar
  | ETVar TyVar
  | STVar TyVar
  | TArr Typ Typ
  | TAllB (Bind TyVar Typ) Typ
  | TIntersection Typ Typ
  | TUnion Typ Typ
  | TTuple [Typ]
  deriving (Generic, Typeable)

pattern TAll :: Bind TyVar Typ -> Typ
pattern TAll bnd <- TAllB bnd TTop
  where
    TAll bnd = TAllB bnd TTop

data PrimOp
  = OpAdd
  | OpSub
  | OpMul
  | OpDiv
  deriving (Eq, Generic)

opTyp :: PrimOp -> Typ
opTyp OpAdd = TArr TInt (TArr TInt TInt)
opTyp OpSub = TArr TInt (TArr TInt TInt)
opTyp OpMul = TArr TInt (TArr TInt TInt)
opTyp OpDiv = TArr TInt (TArr TInt TInt)

data Trm
  = LitInt Integer
  | LitBool Bool
  | Var TmVar
  | Lam (Bind TmVar Trm)
  | App Trm Trm
  | Ann Trm Typ
  | TLamB (Bind TyVar Trm) Typ
  | TApp Trm Typ
  | Let Trm (Bind TmVar Trm)
  | LetRec (Bind TmVar (Trm, Trm))
  | Op PrimOp
  | BinOp PrimOp Trm Trm
  | If Trm Trm Trm
  | Tuple [Trm]
  deriving (Generic, Typeable)

pattern TLam :: Bind TyVar Trm -> Trm
pattern TLam bnd <- TLamB bnd TTop
  where
    TLam bnd = TLamB bnd TTop

instance Alpha Typ

instance Alpha Trm

instance Alpha PrimOp

instance Subst Trm Typ

instance Subst Typ Trm

instance Subst Typ PrimOp

instance Subst Trm PrimOp

instance Subst Typ Typ where
  isvar (TVar v) = Just (SubstName v)
  isvar (ETVar v) = Just (SubstName v)
  isvar (STVar v) = Just (SubstName v)
  isvar _ = Nothing

instance Subst Trm Trm where
  isvar (Var v) = Just (SubstName v)
  isvar _ = Nothing

showsPrecTyp :: Int -> Typ -> FreshM ShowS
showsPrecTyp _ TInt = return $ showString "Int"
showsPrecTyp _ TBool = return $ showString "Bool"
showsPrecTyp _ TTop = return $ showString "⊤"
showsPrecTyp _ TBot = return $ showString "⊥"
showsPrecTyp _ (TVar x) = return $ shows x
showsPrecTyp _ (ETVar x) = return $ showString "^" . shows x
showsPrecTyp _ (STVar x) = return $ showString "~" . shows x
showsPrecTyp p (TArr a b) = do
  a' <- showsPrecTyp 1 a
  b' <- showsPrecTyp 0 b
  return $ showParen (p > 0) $ a' . showString " -> " . b'
showsPrecTyp p (TAll bnd) = do
  (x, t) <- unbind bnd
  t' <- showsPrecTyp 0 t
  return $ showParen (p > 0) $ showString "∀" . shows x . showString ". " . t'
showsPrecTyp p (TAllB bnd b) = do
  (x, t) <- unbind bnd
  t' <- showsPrecTyp 0 t
  b' <- showsPrecTyp 0 b
  return $ showParen (p > 0) $ showString "∀(" . shows x . showString " <: " . b' . showString "). " . t'
showsPrecTyp p (TIntersection a b) = do
  -- TODO: I am unsure about the number
  a' <- showsPrecTyp 1 a
  b' <- showsPrecTyp 1 b
  return $ showParen (p > 0) $ a' . showString " & " . b'
showsPrecTyp p (TUnion a b) = do
  -- TODO: I am unsure about the number
  a' <- showsPrecTyp 1 a
  b' <- showsPrecTyp 1 b
  return $ showParen (p > 0) $ a' . showString " | " . b'
showsPrecTyp _ (TTuple ts) = do
  ts' <- mapM (showsPrecTyp 0) ts
  return $ showString "(" . foldr1 (\a b -> a . showString ", " . b) ts' . showString ")"

instance Show Typ where
  showsPrec prec ty = runFreshM $ showsPrecTyp prec ty

showOp :: PrimOp -> ShowS
showOp OpAdd = showString "+"
showOp OpSub = showString "-"
showOp OpMul = showString "*"
showOp OpDiv = showString "/"

instance Show PrimOp where
  showsPrec _ = showParen True . showOp

showsPrecTrm :: Int -> Trm -> FreshM ShowS
showsPrecTrm _ (LitInt i) = return $ shows i
showsPrecTrm _ (LitBool b) = return $ shows b
showsPrecTrm _ (Var x) = return $ shows x
showsPrecTrm p (Lam bnd) = do
  (x, e) <- unbind bnd
  e' <- showsPrecTrm 0 e
  return $ showParen (p > 0) $ showString "λ" . shows x . showString ". " . e'
showsPrecTrm p (App e1 e2) = do
  e1' <- showsPrecTrm 9 e1
  e2' <- showsPrecTrm 10 e2
  return $ showParen (p > 9) $ e1' . showString " " . e2'
showsPrecTrm p (Ann e t) = do
  e' <- showsPrecTrm 1 e
  return $ showParen (p > 1) $ e' . showString " : " . shows t
showsPrecTrm p (TLam bnd) = do
  (a, e) <- unbind bnd
  e' <- showsPrecTrm 0 e
  return $ showParen (p > 0) $ showString "Λ" . shows a . showString ". " . e'
showsPrecTrm p (TLamB bnd b) = do
  (a, e) <- unbind bnd
  e' <- showsPrecTrm 0 e
  b' <- showsPrecTyp 0 b
  return $ showParen (p > 0) $ showString "Λ(" . shows a . showString " <: " . b' . showString "). " . e'
showsPrecTrm p (TApp e t) = do
  e' <- showsPrecTrm 9 e
  t' <- showsPrecTyp 10 t
  return $ showParen (p > 9) $ e' . showString " @" . t'
showsPrecTrm p (Let e1 bnd) = do
  (x, e2) <- unbind bnd
  e1' <- showsPrecTrm 0 e1
  e2' <- showsPrecTrm 0 e2
  return $ showParen (p > 0) $ showString "let " . shows x . showString " = " . e1' . showString " in " . e2'
showsPrecTrm p (LetRec bnd) = do
  (x, (e1, e2)) <- unbind bnd
  e1' <- showsPrecTrm 0 e1
  e2' <- showsPrecTrm 0 e2
  return $ showParen (p > 0) $ showString "letrec " . shows x . showString " = " . e1' . showString " in " . e2'
showsPrecTrm _ (Op op) = return $ shows op
showsPrecTrm p (BinOp op e1 e2) | op `elem` [OpAdd, OpSub] = do
  e1' <- showsPrecTrm 6 e1
  e2' <- showsPrecTrm 7 e2
  return $ showParen (p > 6) $ e1' . showString " " . showOp op . showString " " . e2'
showsPrecTrm p (BinOp op e1 e2) = do
  e1' <- showsPrecTrm 7 e1
  e2' <- showsPrecTrm 8 e2
  return $ showParen (p > 7) $ e1' . showString " " . showOp op . showString " " . e2'
showsPrecTrm p (If e1 e2 e3) = do
  e1' <- showsPrecTrm 0 e1
  e2' <- showsPrecTrm 0 e2
  e3' <- showsPrecTrm 0 e3
  return $ showParen (p > 0) $ showString "if " . e1' . showString " then " . e2' . showString " else " . e3'
showsPrecTrm _ (Tuple es) = do
  es' <- mapM (showsPrecTrm 0) es
  return $ showString "(" . foldr1 (\a b -> a . showString ", " . b) es' . showString ")"

instance Show Trm where
  showsPrec prec tm = runFreshM $ showsPrecTrm prec tm
