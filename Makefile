lint:
	flake8 altcosa scripts \
		--count \
		--statistics \
		--append-config=.flake8 \
		--show-source

type-check:
	mypy --config-file=.mypy.ini --pretty altcosa scripts
