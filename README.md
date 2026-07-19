Dilo
===

Dilo is a gradual rewrite of kilo editor (https://github.com/antirez/kilo) to D.
learn how to gradually convert software from C to D.

this seperated in 2 attempts. first one is a 'top down' approach,
translating main and then functions called by main and so on. this
worked while i was just translating syntax to D, but when i was
rewriting nul-term strings into proper arrays and other stuff
a bunch of bugs appeared.

the second attempt is a 'bottow up' one, first translate the
functions and structs that dont have dependecies on other kilo
code, then translate functions that call the new D functions
and so on. i want to see wich approach is better.


Usage: dilo `<filename>`

Keys:

    CTRL-S: Save
    CTRL-Q: Quit
    CTRL-F: Find string in file (ESC to exit search, arrows to navigate)

Kilo was written by Salvatore Sanfilippo aka antirez and is released
under the BSD 2 clause license.
