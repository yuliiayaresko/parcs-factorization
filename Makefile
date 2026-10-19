all: run

clean:
	rm -f out/Factorize.jar out/TrialDivision.jar

out/Factorize.jar: out/parcs.jar src/Factorize.java
	@javac -cp out/parcs.jar -d src src/Factorize.java
	@jar cf out/Factorize.jar -C src Factorize.class
	@rm -f src/Factorize.class

out/TrialDivision.jar: out/parcs.jar src/TrialDivision.java
	@javac -cp out/parcs.jar -d src src/TrialDivision.java
	@jar cf out/TrialDivision.jar -C src TrialDivision.class
	@rm -f src/TrialDivision.class

build: out/Factorize.jar out/TrialDivision.jar

run: build
	@cd out && java -cp 'parcs.jar:Factorize.jar' Factorize
