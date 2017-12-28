install() {
	if [ ! -d "ext" ]; then
		mkdir ext
		cd ext
		git clone git@bitbucket.org:planetarysystemresearch/jvie_t_matrix
		git clone git@bitbucket.org:planetarysystemresearch/fastmm
		cd ..
	fi
	
	make
	
	./scadyn -mesh examples/GRE-1.h5 -T examples/T-GRE-1.h5
}

install
