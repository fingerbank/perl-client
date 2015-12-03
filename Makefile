SHELL = /bin/bash

init-db-local:
		@db/upgrade.pl --database db/fingerbank_Local.db; \
		chown fingerbank.fingerbank /usr/local/fingerbank/db/fingerbank_Local.db; \
		chmod 664 /usr/local/fingerbank/db/fingerbank_Local.db; \

init-db-upstream:
		@read -p "API key (ENTER if none): " api_key; \
        perl -I/usr/local/fingerbank/lib -Mfingerbank::DB -Mfingerbank::Util -Mfingerbank::Log -e "fingerbank::Log::init_logger; fingerbank::DB::update_upstream( (api_key => \"$$api_key\") )"; \
		chown fingerbank.fingerbank /usr/local/fingerbank/db/fingerbank_Upstream.db; \
		chmod 664 /usr/local/fingerbank/db/fingerbank_Upstream.db; \

init-p0f-map:
		@read -p "API key (ENTER if none): " api_key; \
		perl -I/usr/local/fingerbank/lib -Mfingerbank::Config -Mfingerbank::Util -Mfingerbank::Log -e "fingerbank::Log::init_logger; fingerbank::Config::update_p0f_map( (api_key => \"$$api_key\") )"; \

package-files:
		@read -p "Version (X.Y.Z): " version; \
		read -p "Branch: " branch; \
		tmp_dir=fingerbank-$$version; \
		echo Building package files tgz for fingerbank-$$version; \
		if [ -d $$tmp_dir ]; then \
			echo "Destination for git clone ($$tmp_dir) already exists"; \
		else \
			mkdir $$tmp_dir; \
			git clone https://github.com/fingerbank/perl-client.git $$tmp_dir; \
			if [ -n $$branch ]; then \
				cd $$tmp_dir ; \
				git checkout $$branch ; \
				cd .. ; \
			fi ; \
			rm -f $$tmp_dir/README.md; \
			rm -rf $$tmp_dir/t; \
			read -p "API key: " api_key; \
			perl -I$$tmp_dir/lib -Mfingerbank::DB -Mfingerbank::Util -Mfingerbank::Log '-MLog::Log4perl qw(:easy)' -e "Log::Log4perl->easy_init(\$$INFO); fingerbank::DB::update_upstream( (api_key => \"$$api_key\", download_url => \"https://fingerbank.inverse.ca/api/v1/download\", destination => \"$$tmp_dir/db/fingerbank_Upstream.db\") )"; \
			perl -I$$tmp_dir/lib -Mfingerbank::Config -Mfingerbank::Util -Mfingerbank::Log '-MLog::Log4perl qw(:easy)' -e "Log::Log4perl->easy_init(\$$INFO); fingerbank::Config::update_p0f_map( (api_key => \"$$api_key\", download_url => \"https://fingerbank.inverse.ca/api/v1/download-p0f-map\", destination => \"$$tmp_dir/conf/fingerbank-p0f.fp\") )"; \
			tar -czf fingerbank.tar.gz $$tmp_dir; \
			rm -rf $$tmp_dir; \
		fi \

test:
	FINGERBANK_KEY=$$api_key perl t/smoke.t

full-test:
	@read -p "API key (ENTER if none): " api_key; \
	FINGERBANK_KEY=$$api_key perl t/smoke.t
