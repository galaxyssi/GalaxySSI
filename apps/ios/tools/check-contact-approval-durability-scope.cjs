// Source contracts only. No native storage-failure/MQTT/device acceptance.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../../..'),sha='07156a44cd4494b6121a7d0ea255aa16210f905f',base='03b6b3aee4ddfe50fd859d4063ec4361f86e29cb';
const git=args=>cp.execFileSync('git',args,{cwd:root,maxBuffer:16000000});
const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'),source=name=>read('apps/ios/GalaxySSI/'+name+'.swift');
const prior=name=>git(['show',base+':apps/ios/GalaxySSI/'+name+'.swift']).toString().replace(/\r\n/g,'\n');
const check=(text,tokens)=>{for(const token of tokens)assert(text.includes(token),token);};
const changed=git(['diff','--name-status','--no-renames',sha+'^1',sha]).toString().trim().split(/\r?\n/).map(line=>line.split('\t'));assert.equal(changed.length,4);
const inventory={schema:1,source:{androidPR:3262,mergeCommit:sha,priorIOSPR:3326,note:'Existing approval readiness was already ported. This is a narrow native durability follow-up, not a duplicate full transport port.'},files:changed.map(([status,file])=>({path:file,status,sha256:crypto.createHash('sha256').update(git(['show',sha+':'+file])).digest('hex')}))};
const store=source('GalaxySSIStore'),routes=source('MqttPeerRoutes'),services=source('GalaxySSIServices');
const snapshot='    let previousRequests = friendRequests, previousContacts = contacts\n';
const rollback='    guard save() else {\n      friendRequests = previousRequests\n      contacts = previousContacts\n      return false\n    }';
const approval=store.split('  func approveFriendRequest(id:')[1].split('  func approveFriendRequest(galaxySSIId:')[0];
check(approval,[snapshot.trim(),rollback.trim(),'upsert(next)','if request.opaquePhoneRoutes != nil']);
assert(approval.indexOf(snapshot)<approval.indexOf('request.status = .approved'));
assert(approval.indexOf(rollback)<approval.indexOf('appendSystemNotification('));
const normalized=store.replace(snapshot,'').replace(rollback,'    save()')
  .replace('    commitOwnedAgentTaskState(expected: expected, updated: updated)\n  }\n\n  func commitOwnedAgentTaskState(expected: AgentTaskRecord?, updated: AgentTaskRecord) -> Bool {\n','');
assert.equal(normalized,prior('GalaxySSIStore'),'Only approval rollback and #3119 shared task-commit wrapper; original commit body, identities, other persistence and schedule guards exact');
for(const name of ['MqttPeerRoutes','MqttPeerRouteSession','GalaxySSIMqttClient','GalaxySSIEncryptedStateStore','GalaxySSISignalEngine','GalaxySSIAddContactView','GalaxySSIAgentDirectoryView','GalaxySSIFriendRequestDetailView'])assert.equal(source(name),prior(name),name+' unchanged');
// #3119 extends unrelated Auto routing in this class; keep approval kernels exact.
for(const signature of ['  func publishPhoneContactDecision(', '  private func refreshApprovedPhoneContactSubscriptions(', '  private func handlePhoneContactIncoming(']) {
 const method=text=>{const start=text.indexOf(signature);assert(start>=0,signature);const end=text.indexOf('\n  }\n',start);assert(end>start,signature);return text.slice(start,end+5);};
 assert.equal(method(services),method(prior('GalaxySSIServices')),signature+' unchanged');
}
check(routes,['existing.identity == identity','!peer.binding.enabled && binding.enabled','peer.session.setEnabled(binding.enabled)','return newlyEnabled.filter { peers[$0].map(ready) ?? false }','enabled.forEach(onReady)']);
check(services,['if approved { refreshApprovedPhoneContactSubscriptions() }','notifyWhenReady: true','scheduleOutboxFlush(after: 0)','store.approveFriendRequest(galaxySSIId: request.galaxySSIId) else { return }']);
const tests='apps/ios/GalaxySSITests/GalaxySSIStoreTests.swift';check(read(tests),['testContactApprovalRollsBackWhenEncryptedStateCannotBeSaved','rejectStateWrites = true','XCTAssertFalse(store.approveFriendRequest(id: request.id))','XCTAssertEqual(store.friendRequests, requests)','XCTAssertEqual(store.contacts, contacts)','XCTAssertEqual(store.messagesByContact, messages)','XCTAssertEqual(defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey), encrypted)','projection.currentPeers().first','let reopened = GalaxySSIStore','let approved = GalaxySSIStore']);
check(read('apps/ios/GalaxySSITests/MqttPeerRoutesTests.swift'),['testApprovalEnablesWarmHandshakeAndRevocationInvalidatesPreparedPacket','testConnectedBrokerIsNotReadyUntilMatchingPeerAcknowledgement','testDisabledPairCannotForwardBusinessIngress']);
const coverage={schema:1,source:inventory.source,verification:'source-contracts-not-native-execution',files:inventory.files.map(file=>{
 const name=path.basename(file.path);let kind,ios,note;
 if(name==='AppStore.kt'){kind='native-durability-follow-up';ios=['apps/ios/GalaxySSI/GalaxySSIStore.swift',tests];note='Prior #3326 already refreshed native approval subscriptions/outbox. Current iOS approval ignored save() failure; now capture contact/request arrays before mutation, return false and restore them if encrypted state save fails, before system notice or callers can enter their success refresh/recovery branch. New fixture sources cover exact state bytes, route remaining disabled, unrelated contact and messages preserved, reopen and successful retry. Not executed.';}
 else if(name==='MqttPeerRoutes.kt'){kind='already-present-production-parity';ios=['apps/ios/GalaxySSI/MqttPeerRoutes.swift','apps/ios/GalaxySSI/MqttPeerRouteSession.swift','apps/ios/GalaxySSI/GalaxySSIServices.swift'];note='Existing identity-preserving replace detects disabled-to-enabled binding, changes enabled flag without resetting same-identity handshake, and emits onReady only for ready authenticated peers. Legacy approval refresh and immediate outbox wake already exist. Peer route files and approval service kernels remain exact; unrelated Auto routing additions in the service class are owned by #3119. No new transport delta is claimed.';}
 else if(name==='MqttPeerRoutesTest.kt'){kind='android-unit-source-reference';ios=['apps/ios/GalaxySSITests/MqttPeerRoutesTests.swift',tests];note='Android warm-handshake approval, repeated refresh, unrelated peer, unauthenticated/disabled-route expectations reviewed. Existing native route fixture sources retained; one native approval-save failure/reopen/retry fixture added but not run. No socket/paired-device/handshake timing acceptance.';}
 else{assert.equal(name,'build.gradle.kts');kind='android-version-only';ios=[];note='No iOS version bump or IPA.';}
 return{source:file.path,sourceSHA256:file.sha256,kind,ios,note};
})};
for(const[suffix,value]of[['SOURCE_INVENTORY',inventory],['PORT_COVERAGE',coverage]]){const file='apps/ios/ANDROID_3262_'+suffix+'.json',content=JSON.stringify(value,null,2)+'\n';if(process.argv.includes('--write'))fs.writeFileSync(path.join(root,file),content);else assert.equal(read(file),content);}
console.log('Android #3262: four pinned file dispositions; existing #3326 transport port retained, failed approval-save rollback follow-up isolated. Source-only evidence, not native execution.');
