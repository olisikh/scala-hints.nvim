.PHONY: test test-zio test-cats-effect test-cats test-libs

NVIM_TEST := nvim --headless --clean -u tests/minimal_init.lua
PLENARY_OPTS := {minimal_init = 'tests/minimal_init.lua'}

# Run all tests
test:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/ $(PLENARY_OPTS)"

# Run ZIO query tests
test-zio:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/zio/ $(PLENARY_OPTS)"

# Run Cats-Effect query tests
test-cats-effect:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/cats-effect/ $(PLENARY_OPTS)"

# Run Cats tagless-final query tests
test-cats:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/cats/ $(PLENARY_OPTS)"

# Run all library query tests
test-libs: test-zio test-cats-effect test-cats
