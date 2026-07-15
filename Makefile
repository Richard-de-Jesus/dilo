all: kilo

kilo: kilo.c
	dmd dilo.d kilo.c
	
clean:
	rm kilo
