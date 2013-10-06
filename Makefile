# header-less version for saltybookie.pl
ratings.noheader.csv : ratings.raw.csv
	< $^ tail -n +2 > $@

# Excel likes to mangle "009" into "9"; I fix that here rather than fight Excel
ratings.raw.csv : saltybookie.r matches.in.csv
	Rscript --vanilla saltybookie.r | sed '0,/^"9",/ s/^"9",/"009",/' > $@

# exclude data to be excluded
matches.in.csv : matches.all.csv
	< $^ grep '^[e05]' | sed "s/,\\([^,\"']*'[^,]*\\)/,\"\\1\"/g" > $@

.PHONY : clean seven

clean :
	rm matches.in.csv ratings.raw.csv ratings.noheader.csv

seven :
	< matches.all.csv grep '^[e057]' | sed "s/,\\([^,\"']*'[^,]*\\)/,\"\\1\"/g" > matches.in.csv

