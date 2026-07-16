import kilo;

import std.stdio : writeln;
import std;

// resolve conflicts between libc and core.stdc.
// we prefer D's version, more type safety.
alias libc = core.stdc;
alias cio = libc.stdio; 

/* making clear that kilo namespace is used
 to resolve conflicts between symbols built in C
  and D's reimport of those symbols in core.* */
alias cbuiltin = kilo;

/* Load the specified program in the editor memory and returns 0 on success
 * or 1 on error. */
int editorOpen(char *filename) {
    cio.FILE *fp;

    kilo.E.dirty = 0;
    free(kilo.E.filename);
    size_t fnlen = strlen(filename)+1;
    kilo.E.filename = cast(char*) malloc(fnlen);
    memcpy(kilo.E.filename,filename,fnlen);

    fp = cio.fopen(filename,"r");
    if (!fp) {
        if (errno != ENOENT) {
            cio.perror("Opening file");
            exit(1);
        }
        return 1;
    }

    char *line = null;
    size_t linecap = 0;
    cbuiltin.ssize_t linelen;
    // cast away the shared in fp.
    while((linelen = getline(&line,&linecap, cast(cbuiltin._IO_FILE*) fp)) != -1) {
        if (linelen && (line[linelen-1] == '\n' || line[linelen-1] == '\r'))
            line[--linelen] = '\0';
        editorInsertRow(kilo.E.numrows,line,linelen);
    }
    free(line);
    fclose(fp);
    kilo.E.dirty = 0;
    return 0;
}

/* Select the syntax highlight scheme depending on the filename,
 * setting it in the global state E.syntax. */
void editorSelectSyntaxHighlight(const char* filename)
{
    for (size_t j = 0; j < HLDB_ENTRIES; j++)
    {
        editorSyntax* s = &HLDB[j];
        size_t i = 0;
        while (s.filematch[i])
        {
            char* p;
            size_t patlen = strlen(s.filematch[i]);
            if ((p = strstr(filename, s.filematch[i])) != NULL)
            {
                if (s.filematch[i][0] != '.' || p[patlen] == '\0')
                {
                    kilo.E.syntax = s;
                    return;
                }
            }
            i++;
        }
    }
}

extern (C)
void handleSigWinCh(int unused)
{

    updateWindowSize();
    if (kilo.E.cy > kilo.E.screenrows)
        kilo.E.cy = kilo.E.screenrows - 1;
    if (kilo.E.cx > kilo.E.screencols)
        kilo.E.cx = kilo.E.screencols - 1;
    editorRefreshScreen();
}

void initEditor()
{
    kilo.E.cx = 0;
    kilo.E.cy = 0;
    kilo.E.rowoff = 0;
    kilo.E.coloff = 0;
    kilo.E.numrows = 0;
    kilo.E.row = null;
    kilo.E.dirty = 0;
    kilo.E.filename = null;
    kilo.E.syntax = null;
    updateWindowSize();
    // dmd complains about the function being type void.
    extern (C) void function(int) han = &handleSigWinCh;
    // added 0 arg, dmd is more strict.
    signal(SIGWINCH, han);
}

int main(string[] args)
{
    if (args.length != 2)
    {
        writeln(std.stdio.stderr, "Usage: dilo <filename>");
        // exit is imported from kilo, wich imports stdlib.h
        exit(1);
    }
    // append null terminator to 2nd arg
    // make it compatible with C code.
    char[] filename = cast(char[])(args[1] ~ '\0');

    initEditor();
    editorSelectSyntaxHighlight(filename.ptr);
    editorOpen(filename.ptr);
    enableRawMode(STDIN_FILENO);

    char[] msg = "HELP: Ctrl-S = save | Ctrl-Q = quit | Ctrl-F = find".dup;
    editorSetStatusMessage(msg.ptr);

    while (true)
    {
        editorRefreshScreen();
        editorProcessKeypress(STDIN_FILENO);
    }

    return 0;
}
