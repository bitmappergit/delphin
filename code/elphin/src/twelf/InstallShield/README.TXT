Twelf
Copyright (C) 1997, 1998, Frank Pfenning and Carsten Schuermann

Authors: Frank Pfenning
	 Carsten Schuermann
With contributions by:
	 Iliano Cervasato
	 Jeff Polakow

Twelf is an implementation of

 - the LF logical framework, including type reconstruction
 - the Elf constraint logic programming language
 - a meta-theorem prover for LF (very preliminary)
 - an Emacs interface

This README file applies to version Twelf 1.2. It describes the
self-extracting EXE file for Windows 95/98/NT for the Twelf server
only. For current information regarding Twelf, see the Twelf home page
at

  http://www.cs.cmu.edu/~twelf


Files:
======

 README.TXT   --- this file
 README.FINAL --- final installation message 
 INSTALL.TXT  --- installation file (for source distribution)
 bin/         --- utility scripts and heap location
 doc/         --- Twelf user's guide in various formats
 emacs/       --- Emacs interface for Twelf
 examples/    --- various case studies


Twelf has been tested to work with NTEmacs which is freely 
available from the 

     University of Washington:
 	ftp://ftp.cs.washington.edu/pub/ntemacs


Installation Instructions
=========================

Download and run

  http://www.cs.cmu.edu/~twelf/dist/twelf-1-2.exe

and follow the instructions of the Installation Wizard.

After completing the installation, you should add the line
    
  (load "C:/Twelf/emacs/twelf-init.el")
    
to your _emacs file if you want to use the Twelf server from NT Emacs
(recommended).
       
To test the installation, select "Twelf Server" from the Start menu

  Twelf 1.2, Aug 27 1998
  %% OK %%

You can now load the examples from the User's Guide and pose an
example query as shown below.  The prompt from the Twelf top-level is
`?-'.  To drop from the Twelf top-level to the ML top-level, type C-c
(CTRL c).  To exit the Twelf server you may issue the quit command.

  Config.read examples\guide\sources.cfg
  Config.load
  top
  ?- of (lam [x] x) T.
  Solving...
  T = arrow T1 T1.
  More? y
  No more solutions
  ?- C-c
  interrupt
  %% OK %%
  quit


Uninstallation Instructions
===========================

Select Setting SubMenu from the Start Menu.
Select Control Panel
Select Add/Remove programs
Select "Twelf 1.2" from the list and click the Add/Remove Button
Click twice "OK"


