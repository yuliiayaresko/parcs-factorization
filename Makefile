# Компіляція йде в окремі теки build/*, а jar пакується з усієї теки цілком.
# Так у архів потрапляють і вкладені класи (Factorize$Settings), про які легко забути,
# якщо перелічувати файли поіменно.
#
# -encoding UTF-8 обов'язковий: у текстах є кирилиця, а типове кодування
# компілятора залежить від локалі системи.

JAVAC = javac -encoding UTF-8 -cp out/parcs.jar
JAR   = jar

all: run

clean:
	rm -rf build out/Factorize.jar out/TrialDivision.jar

out/Factorize.jar: out/parcs.jar src/Factorize.java
	@mkdir -p build/app
	@$(JAVAC) -d build/app src/Factorize.java
	@$(JAR) cf out/Factorize.jar -C build/app .
	@rm -rf build/app

out/TrialDivision.jar: out/parcs.jar src/TrialDivision.java
	@mkdir -p build/worker
	@$(JAVAC) -d build/worker src/TrialDivision.java
	@$(JAR) cf out/TrialDivision.jar -C build/worker .
	@rm -rf build/worker

build: out/Factorize.jar out/TrialDivision.jar

run: build
	@cd out && java -Dfile.encoding=UTF-8 -cp 'parcs.jar:Factorize.jar' Factorize

.PHONY: all clean build run
