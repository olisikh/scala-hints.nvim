.PHONY: test test-pure test-lsp test-engine

NVIM_TEST := nvim --headless --clean -u tests/minimal_init.lua
PLENARY_OPTS := {minimal_init = 'tests/minimal_init.lua'}

# Run all tests
test:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/ $(PLENARY_OPTS)"

# Run only pure (no-LSP) ZIO query tests
test-pure:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/zio/ $(PLENARY_OPTS)"

# Run only query engine tests
test-engine:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"
