.PHONY: test

FORK_URL=http://127.0.0.1:8545

test:
	forge test --fork-url $(FORK_URL)
