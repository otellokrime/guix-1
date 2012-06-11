;;; Guix --- Nix package management from Guile.         -*- coding: utf-8 -*-
;;; Copyright (C) 2012 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of Guix.
;;;
;;; Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (guix http)
  #:use-module (guix derivations)
  #:use-module (guix utils)
  #:export (http-fetch))

;;; Commentary:
;;;
;;; Produce fixed-output derivations with data fetched over HTTP.
;;;
;;; Code:

(define* (http-fetch store url hash-algo hash
                     #:key name (system (%current-system)))
  "Return the path of a fixed-output derivation in STORE that fetches URL,
which is expected to have hash HASH of type HASH-ALGO (a symbol).  By
default, the file name is the base name of URL; optionally, NAME can specify
a different file name."
  (define builder
    `(begin
       (use-modules (guix build http))
       (http-fetch ,url %output)))

  (build-expression->derivation store (or name (basename url)) system
                                builder '()
                                #:hash-algo hash-algo
                                #:hash hash
                                #:modules '((guix build http))))
