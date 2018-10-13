watchme-test:
	watchmedo shell-command --patterns="*.nim" --recursive --command="nimble test" .