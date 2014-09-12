installer_file = node['private-chef']['installer_file']
installer_name = ::File.basename(installer_file.split('?').first)

if installer_name =~ /^private-chef/ # skip both osc and cs12

  # OPC config data
  # TODO - read this in from /etc/opscode/chef-server-running.json
  opc_bundle = "/opt/opscode/embedded/bin/bundle"
  opscode_account_url = "http://127.0.0.1:9465"
  opscode_account_path = "/opt/opscode/embedded/service/opscode-account"
  superuser_pem = "/etc/opscode/pivotal.pem"
  superuser_name = ::File.basename(superuser_pem).split('.')[0]
  user_root = "/srv/piab/users"
  dev_users = {}

  organizations = {
    'ponyville' => [
        'rainbowdash',
        'fluttershy',
        'applejack',
        'pinkiepie',
        'twilightsparkle',
        'rarity'
    ],
    'wonderbolts' => [
        'spitfire',
        'soarin',
        'rapidfire',
        'fleetfoot'
    ]
  }

  organizations.each do |orgname, users|

    users.each do |username|

      folder = "#{user_root}/#{username}"
      dot_chef = "#{folder}/.chef"

      dev_users[username] = {
        'username' => username,
        'displayname' => username,
        'email' => "#{username}@mylittlepony.com",
        'orgname' => orgname,
        'folder' => folder,
        'private_key' => "#{dot_chef}/#{username}.pem",
        'org_validator' => "#{dot_chef}/#{username}-validator.pem",
        'knife_config' => "#{dot_chef}/knife.rb"
      }

    end
  end

  unless File.exists?("/srv/piab/dev_users_created")
    topology = TopoHelper.new(ec_config: node['private-chef'])

    ruby_block "Waiting for first-time OPC initialization" do
      block do
        attempts = 600
        STDOUT.sync = true

        keepalived_dir = '/var/opt/opscode/keepalived'
        requested_cluster_status_file = ::File.join(keepalived_dir, 'requested_cluster_status')
        cluster_status_file = ::File.join(keepalived_dir, 'current_cluster_status')

        (0..attempts).each do |attempt|
          break if File.exists?(requested_cluster_status_file) &&
            File.open(requested_cluster_status_file).read.chomp == 'master' &&
            File.exists?(cluster_status_file) &&
            File.open(cluster_status_file).read.chomp == 'master'

          sleep 1
          print '.'
          if attempt == attempts
            raise "I'm sick of waiting for server startup after #{attempt} attempts"
          end
        end
        sleep 10
      end
    end

    dev_users.each_pair do |name, options|

      # create the students .chef/ dir
      directory ::File.dirname(options['private_key']) do
        recursive true
        action :create
      end

      # create a knife.rb file for the user
      template "#{options['knife_config']}" do
        source "knife.rb.erb"
        variables(
          :username => options['username'],
          :orgname => options['orgname'],
          :server_fqdn => "api.#{topology.mydomainname}"
        )
        mode "0777"
        action :create
      end

      # create an account on the OPC for the student
      execute "create OPC account #{name}" do
        command <<-EOH
  #{opc_bundle} exec bin/createobjecttool --object-type 'user' -a '#{opscode_account_url}' \
  --object-name #{options['username']} --displayname '#{options['displayname']}' -e '#{options['email']}' \
  -f '#{options['displayname']}' -m '#{options['displayname']}' -l '#{options['displayname']}' \
  --key-path #{options['private_key']} --user-password '#{options['username']}' \
  --opscode-username #{superuser_name} --opscode-private-key #{superuser_pem}
  EOH
        cwd opscode_account_path
      end
    end

    # create the orgs and associate the users
    organizations.each do |orgname, users|

      org_validator = "#{user_root}/#{orgname}-validator.pem"

      ruby_block "create OPC organization #{orgname}" do
        block do
          cmd =<<-EOH
  #{opc_bundle} exec bin/createorgtool -t Business -a '#{opscode_account_url}' \
  --org-name #{orgname} --customer-org-fullname '#{orgname}' \
  --username '#{users.join(' ')}' \
  --client-key-path #{org_validator} \
  --opscode-username #{superuser_name} --opscode-private-key #{superuser_pem}
  EOH
          waiting = true
          while waiting
            opts = {:cwd => opscode_account_path,
                    :returns => [0,53]}
            case shell_out(cmd, opts).exitstatus
            when 53
              Chef::Log.info("...")
              sleep 20
            when 0
              Chef::Log.info("#{orgname} created!")
              waiting = false
            else
              Chef::Log.error("#{orgname} not created...error!")
              waiting = false
            end
          end
        end
      end

    end

    ruby_block 'LOL' do
      block do
        Chef::Log.info <<-EOH


                              .`
                    `,,,,,.`  ;,;
               ,;;;;;''''';;;,:..;                   `        ;;
           .;;;'''''''''''''';,...;                ;;;       ;,;
     `  ,;;;''''''''''''';;;;;,....;              ;:,;      ;..;
      ;;''''''';'''''';;;;;;;:,....,;            ;,,,;   ;:,,..;
       :;;;;'';''''';;;;;;;;;,,.....:.          `;,,,:  ;,,:..,,
          ```;'''';;;;;;;;;;..,...;..;          ;,,,:  :,,;..,:`
            ;''';;;;;;;;;;;.,,:....:.,:         ;,,,;  :,,:...;      :;;;
           ;''';;;;;;;;;;:,,,,;....;..;;`      .,,,,: :,,;....;    .:...;
          ,;';;;;;;;;;;;,,,,.;,....,,.,:;.     ;,,,,. ;,,;...,:   ;....;
         `;';;;;;;;;;;;,,,,,,;......:..';;.    ;,,,: `,,,:...:` .;....,,
         ;';;;;;;;;;;;,,,,,,,,.....:;.,;;;;    ;,,,: ;,,:,...; ;;.....;
        ,;;;;;;;;;;;;;,,,:,,'......,,..;;;';   ;,,,; ;,,:....;.::....:
        ;;;;;;;;;;;;;.,,,'.:...........;;;;;   ;,,,; ;,,;....;;'....,:
       ,;;;;;;;;;;;;,,,,,:,:...........:;;;;.  ;,,,: ;,,'....',,....;
       ;;;;;;;;;;;;;,,,,;,;............,:;;';  ;,,,:,:,,;....';....,.
      `:;;;;;;;;;;;.,,,';;.........,....';;;;  ;,,,,;:,,:,...;:....;
      ;;;;;;;;;;;;;,,,;.;...........,...;;;;;  ;,,,,;:,,:....;....,`
      ;;;;;;;;;;;;,,,;,,.+......;,':.;..:';;;  ;,,,,;,,:,....:....;
     .;;;;;;:;;@;#,,'...;......@@@@:@,..,;;;;  :,,,,::,;.........,,
     ;;;;;;;;;;+;;,;....,...,,@@@@@@.@..,;;;;  .:,,,,;,'.........;             .;
     :;;;::;;;';@#;.........'# +@@@@;...,;;;;,  ;,,,,,,;........,;   ,;;;:   ;;;
    ;;;;; ;;;;;#;,'...,@...@;` `\#@@@....,;;;';  ;,,,:;,;..;;....;` ;,...,: .;;;    .:;;;;;;;;;;,
   `:;;. :;;;+';,: ,..,;@@+ :  `\#@@@....:;;;;;` ;,,:,,::.'..,...;;,......:;;;; .;;'''''''''''''';;`
   ;::   ;;;;;.@@: @....;;  ;. ;@@@#....;;;;;;; ;,:,,,;,'..,,..::........;'';,;;'''''''''';;:::,,,,,
  .:    ,;;;` + ;' @....,,` :;+@@@@'..,:;;;;;;;.,,,,,,;:...,...'........;'';;'''''''''''';,
        ;::      :'#:.....; `;;\#.\#@:..,;;;;;;;;;`:,,,,;:...;...........;;';;''''''';;;;'''';:
        ;:       + @'.....@  ';;:;;;.,;;;;;;;;;;;:,,,,;...,:,........,;;'';''';;;;;;;;;;;;''';
        :        `;@+,.....@  ';,...,;;;;;;';;;;;:,,,:,...;,:,......:;''';;;;;;;;;;;;;;;;;;''';
       `          '::.......',..,...;;;;;;;;;;;;;,,,,;...;,...:,..,;;'''';;;;;;;;;;;;;;;;;;;''';
                   '........,:,,...;;';;;;;;;;;';:,,,,..;....,,.,;,,;;'';;;;;;;;;;;;;;;;;;;;;''';
                  ;,.........,....:;;:;;;;;;;;;';:,,;..:.....;.,::,..,:;;;;;;;;;;;;;;;;;;;;;;;''';
                 .,.,..,..........;,;;;;;;;;;;''';,'........'..........;;;;;;;;;;;;;;;;;;';;;;'''';
                  ;....;.........,,:;;;;;;;;;'''';;........;,,,,......:';;;;;::::;;';;;;;;';;;;'''':
                   ;;;;..........;,:;;;;;;;;;'''';,......,;,...,,....;,.,,,,,,,,,,,,,;';;;;;;;;;''';`
                   `;,........,;;..;;;;;;;;;'''';.......,:.....;...,;;;;;::,,,..,,,,,,.;;;;;;;;;;''';
                     .;;;;;;;;. :,:;;;;;;;;'';'';.......,,....,,.,;:;;;;;;;;;;;;;:.,,,,,,;;;;;;;;''';`
                               ;..;;;;;;;;;;;'';..............;:;;;'''''''''''';;;;;.,,,,:;;;;;;;;''';
                               ;,:;;;;;;;;;;'';............,:;;..;';;:::;;''''''';;;;,,,,.';;;;;;;''';
                              :,.;;;;;;;;;;'';.........,,:;:,....,;       :;''''''';;;:,,,;;;;;;;;;'';
                              ;.:;;;;;;;::'';....;.,.....,,,......:,       `;''';''';;;,,,:;;;;;;;;'';
                             `:.;;;;;;;.:';;......;:.....,:,   :...;        :''';:''';;;.,,;;;;;;;;;';
                             :.:;;;;:.,,;;,.........,:;;:,,     ...,`        ;''; ;'';;;:,.;;;;;;;;;';
                             ;.;;;:...,;;...............` ,    .....;        ;''; :''';;;,.';;;;;;;;';
                             ;;;;....,;;..............,,    , `.:...;        .'';  ;'';;;.,';;;;;,;;';
                            `;;,.....;,................,    `    ..,:`       .'';  ;'';;;.,;;;;;;; ;;;
                            .;..........................,:`  ,  ....:`       :'';  :'';;;.,:;;;;;; `;;
                            ,............................,',,;.,....,`       ;';   ;'';;;.,:;;;;;;  ;;
                            ,............................,'.,:,;....:`      .;;:   ;'';;;.,:;;;;;:  `;
                            ,............................,',,,,:...,;       ;;,   .''';;;,,:;;;;;.   ;
                            .,....................,;,.....';'',:....;      ;;.    ;''';;;,,:;;;;;`   ;
                             :......................;.....;'::,,...,:     .;      ;'';;;;,,,;;;;;,   ,
                  :;;.       ;......................::....,:.,,,..,:`             ;'';;;;,,,;;;;;;
                  ;,,;;;:::;;,;.,....................;,......,,,...;              ;'';;;;,,,;;;;;;
                  ;,,,,,,,,,,,:,:,....................;,.....,:,....;`           .''';;;;.,,;;;;;;
                 `:,,,,,,,,,,,,;:......,............,;:;......:......;;.         ,''';;;;.,,;;;;;;
                 :,,,,,,,,,,,,,,;......'.........,;; ;,:;,....,........:;;:`     :''';;;;.,,;;;;;;
                 ;,,,,,,,,,,,,,,;......;,....,,;;,    ;,,;;,..............,;,    ;''';;;;,,,;;;;;:
                 ;,,,,,,,,,,,,,,:.....,:,::::,`        ;,,,:;,..............;`   ;''';;;:,,,;;;;;.
                .:,,,,,:,:;;;;;;,......,`               ;:,,,:;;,...........,;   ;''';;::,,:;;;;;
                ;,,,,,,::`     ;.......,,                ,;,,,,,;;,..........:;  ;''';;;,,,:;;;;;
                ;,,,,,,:`      ;.......,:                  ;:,,,,,;;,.........;  ;''';;:.,,;;;;;,
                ;,,,,,,,:      :........:                   .;,,,,,,;.........,; ;''';;;.,,;;;;;
               ,:,,,,,,,;     ,,........;                    ::,,,,,,;.........; ;'''':;.,,';;;;
               ;,,,,,,,,:`    ;.........;                     ;,,,,,,:,........:;,;''':;.,,';;;:
               ;,,,,,,,,,;    ;.........:                     ;,,,,,,,;.........; ;''';;.,,';;;,
               ;,,,,,,,,,;`   ,.........:                     ;,,,,,,,:;........;.,'''';,,,';;;.
               ;,,,,,,,,,,;  ..........,,                     :,,,,,,,,;........,; ;'''.;,,;;;;,
               ;,,,,,,,,,,;, ;.........,.                     :,,,,,,,,;.........;` ;'';`;,,;;;:
              `:,,,,,,,,,,,; :.........,`                     :,,,,,,,,;,........:; ,;'; ,:.'';;
              `:,,,,,,,,,,,;;,.........:                      ;,,,,,,,,::.........;  :;;  ::';;;
              `:,,,,,,,,,,,,;.........,;                      ;,,,,,,,,:;,........;:  :':  ::;;;`
               :,,,,,,,,,,,,:,.........;                      ;,,,,,,,,:;.........,;   :;   ,;;;;
               ;,,,,,,,,,,,;...........;                     `:,,,,,,,,:;..........;.   ,;   ,;;;
               ;,,,,,,,,,,,:,..........;                     :,,,,,,,,,;;..........:;    ,:   ,;;;
               :,,,,,,,,,,;...........,.                     ;,,,,,,,,,;;..........,;     `:   ,;;
                ;,,,,,,,,,,...........:`                     ;,,,,,,,,,;;...........;           :;,
                ;,,,,,,,,;............;                     .;,,,,,,,,,;;...........;.           ;:
                `:,,,,,,:.............;                     ;,,,,,,,,,,:;..........,::           .,
                 ;,,,,,;:............,:                     ;,,,,,,,,,,,;...........::            `
                  ;,,;;:.............:`                     ;,,,,,,,,,,`;...........,;
                   :,  :.............;                     ,,,,,,,,,,,: ;,..........,;
                      ;..............;                     ;,,,,,,,,,,:,:............;
                     .:.............,`                    `;,,,,,,,,,,;;,............;`
                     ;..............;                     ;,,,,,,,,,,,.;............,:`
                    :,..............,                    `;,,,,:::::;;`;........,...:;
                    :..............:                     ,,,,,..``     :...,,,::;;;;.
                   ;;;::::::::::;;;;                                   ,;;:`

             .     t#,     L.                       .,
            ;W    ;##W.    EW:        ,ft t        ,Wt
           f#E   :#L:WE    E##;       t#E Ej      i#D.
         .E#f   .KG  ,#D   E###t      t#E E#,    f#f
        iWW;    EE    ;#f  E#fE#f     t#E E#t  .D#i
       L##Lffi f#.     t#i E#t D#G    t#E E#t :KW,     .......
      tLLG##L  :#G     GK  E#t  f#E.  t#E E#t t#f      GEEEEEEf.
        ,W#i    ;#L   LW.  E#t   t#K: t#E E#t  ;#G
       j#E.      t#f f#:   E#t    ;#W,t#E E#t   :KE.
     .D#j         f#D#;    E#t     :K#D#E E#t    .DW:
    ,WK,           G#t     E#t      .E##E E#t      L#,
    EG.             t      ..         G#E E#t       jt
    ,                                  fE ,;.
                                        ,
                               L.                          t#,         t#,
  j.                       t   EW:        ,ft .           ;##W.       ;##W.
  EW,                   .. Ej  E##;       t#E Ef.        :#L:WE      :#L:WE             ..       :
  E##j                 ;W, E#, E###t      t#E E#Wi      .KG  ,#D    .KG  ,#D           ,W,     .Et
  E###D.              j##, E#t E#fE#f     t#E E#K#D:    EE    ;#f   EE    ;#f         t##,    ,W#t
  E#jG#W;            G###, E#t E#t D#G    t#E E#t,E#f. f#.     t#i f#.     t#i       L###,   j###t
  E#t t##f         :E####, E#t E#t  f#E.  t#E E#WEE##Wt:#G     GK  :#G     GK      .E#j##,  G#fE#t
  E#t  :K#E:      ;W#DG##, E#t E#t   t#K: t#E E##Ei;;;;.;#L   LW.   ;#L   LW.     ;WW; ##,:K#i E#t
  E#KDDDD###i    j###DW##, E#t E#t    ;#W,t#E E#DWWt     t#f f#:     t#f f#:     j#E.  ##f#W,  E#t
  E#f,t#Wi,,,   G##i,,G##, E#t E#t     :K#D#E E#t f#K;    f#D#;       f#D#;    .D#L    ###K:   E#t
  E#t  ;#W:   :K#K:   L##, E#t E#t      .E##E E#Dfff##E,   G#t         G#t    :K#t     ##D.    E#t
  DWi   ,KK: ;##D.    L##, E#t ..         G#E jLLLLLLLLL;   t           t     ...      #G      ..
             ,,,      .,,  ,;.             fE                                          j
                                            ,
  EOH
      end
    end

    file "/srv/piab/dev_users_created" do
      content "Canned dev users and organization created successfully at #{Time.now}"
      action :create
    end
  end
end
