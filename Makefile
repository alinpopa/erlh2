ERL ?= erl
APP := erlh2

.PHONY: deps

all: deps compile eunit

compile:
	@./rebar compile

eunit:
	@./rebar eunit

deps:
	@./rebar get-deps

clean:
	@./rebar clean

distclean: clean
	@./rebar delete-deps

start: all
	$(ERL) -pa $(PWD)/ebin $(PWD)/deps/*/ebin -boot start_sasl -s erlh2

docs:
	@erl -noshell -run edoc_run application '$(APP)' '"."' '[]'
