watchme-test:
	watchmedo shell-command --patterns="*.nim" --recursive --command="nimble test" .

doc:
	nimble doc src/markdown
	mkdir -p docs
	cp src/markdown.html docs
