#!/bin/bash

q="contracts+language:solidity"
outfolder="results"
for page in {1..2}; do
  echo "Page: $page"
  curl -s -o "$outfolder/p${page}".json -H "Accept: application/vnd.github+json" "https://api.github.com/search/repositories?q=$q&page=$page"
  for repo in $(cat "$outfolder/p${page}.json" | jq -r '.items[] | [.name, .clone_url, .full_name] | join(",")')
  do
    prevIFS=$IFS
    IFS=','
    echo $repo
    sarr=($repo)
    IFS=$prevIFS
    name="${sarr[0]}"
    clone_url="${sarr[1]}"
    fullname="${sarr[2]}"
    

    if grep -q "$fullname" "$outfolder/scan_${page}.log" 
    then
      echo "Already scanned, skipping"
      continue
    fi
    echo "Full name: $fullname, name: $name clone url: $clone_url"
    
    rm -rf temp
    mkdir temp
    pushd temp
    git clone ${sarr[1]}
    pushd ${sarr[0]}
    detectionsFile="../../$outfolder/p${page}-${name}.json"
    gitleaks detect -r $detectionsFile
    for secret in $(cat $detectionsFile | jq -r '.[] | select(.RuleID == "ethereum-priv-key") | .Secret' | sort -u) 
    do
      code="w=new Wallet('$secret'); if (w!=null) w.address"
      echo "Code to eval: $code"
      address=$(ethers eval "$code")
      nfoFile="../../$outfolder/p${page}-nfo.txt"
      # use awk '/Balance/{if ($2 != "0.0") print $2}'  results/p1-nfo.txt  to extract addresses with non-zero balances
      if [ $? -eq 0 ]; then
        echo "pk: $secret" >> $nfoFile
        ethers info $address --rpc https://eth.llamarpc.com --network mainnet >> $nfoFile
        echo "==============================" >> $nfoFile
      fi 
    done

    scanfile="../../${outfolder}/scan_${page}.log"
    echo ${fullname} >> $scanfile
    popd
    popd
  done
done