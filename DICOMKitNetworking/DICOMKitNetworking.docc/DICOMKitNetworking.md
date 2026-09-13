# ``DICOMKitNetworking``

DIMSE association services and DICOMweb/DICOM JSON for DICOMKit — the network
code path a local-file viewer does not need.

## Overview

This product adds everything that opens a socket or speaks HTTP, so a
consumer that never needs to send or receive over a network — most viewers —
can leave it out entirely. It depends only on `DICOMKit`, not on
`DICOMKitAuthoring`: where a DIMSE service needs to encode a dataset (for
example C-STORE), it calls `DICOMKit`'s own
`DICOMFile.encodedDatasetData(transferSyntax:sequenceLengthEncoding:)` rather
than reaching for a Part 10 file writer, keeping this product's dependency
graph free of the authoring/anonymization surface.

``DICOMwebClient`` provides an async HTTP foundation for QIDO-RS study,
series, and instance searches; WADO-RS instance, metadata, rendered image,
thumbnail, frame, and BulkData retrieval; and STOW-RS multipart storage.
Inject a ``DICOMwebTransport`` to add application-specific authentication or
to test requests without a network connection. ``DICOMJSONDataset`` converts
`DICOMKit`'s `DICOMDataset` to and from typed DICOM JSON (PS3.18 Annex F).

``DICOMAssociation`` is a transport-independent DIMSE actor backed by a
caller-supplied ``DICOMULTransport``. ``NetworkDICOMULTransport`` implements TCP
or explicitly configured TLS with Network.framework, and
``NetworkDICOMULListener`` accepts inbound connections. Association negotiation
covers Implementation Class UID and Version Name, SCP/SCU Role Selection,
Asynchronous Operations Window, and User Identity, and the actor reports a peer
A-ABORT or A-RELEASE-RQ rather than treating it as an unexpected PDU.

As an SCU, ``DICOMAssociation`` performs C-ECHO, C-STORE, C-FIND, C-MOVE,
C-GET, and C-CANCEL, returning a classified ``DICOMDIMSEStatus`` and, for
C-MOVE and C-GET, ``DICOMSubOperationCounts``. C-GET takes an `onStore`
handler: the peer returns each matching instance as a C-STORE sub-operation on
a storage presentation context, and the handler's returned status is sent back
in the C-STORE-RSP. As an SCP, it accepts an
association against a ``DICOMAssociationPolicy``, receives requests through
``DICOMAssociation/receiveRequest()``, and answers them with the matching
`respondTo…` method. Applications negotiate one presentation context per SOP
Class — `DICOMSOPClass` (in `DICOMKit`) lists the common UIDs — and can use
the SOP Class convenience overloads instead of passing context identifiers.
This is a protocol foundation, not a clinical interoperability or PACS
conformance claim.

``DICOMAssociation`` also performs the DIMSE-N (Normalized) services —
N-CREATE, N-SET, N-GET, N-ACTION, N-DELETE, and N-EVENT-REPORT — as both SCU
(returning a classified ``DICOMNServiceResult``) and SCP (the matching
`respondToN…` responders). Unlike the DIMSE-C services, whether an N-service
message carries a data set is conditional rather than fixed by the command
kind, which ``DICOMAssociation/receiveRequest()`` already handles generically through
``DICOMDIMSECommand/hasDataset``. Two Normalized workflows are built on top:
Storage Commitment Push Model, through
``DICOMAssociation/requestStorageCommitment(messageID:contextID:_:)`` and
``DICOMStorageCommitmentRequest``/``DICOMStorageCommitmentResult`` — note that
the commitment result is *not* the N-ACTION response, but arrives later as an
N-EVENT-REPORT, either on the same association (via SCP/SCU role selection)
or a fresh inbound one (via ``NetworkDICOMULListener``); and Modality
Performed Procedure Step, through
``DICOMAssociation/createPerformedProcedureStep(messageID:contextID:sopInstanceUID:attributes:transferSyntax:)``
and
``DICOMAssociation/updatePerformedProcedureStep(messageID:contextID:sopInstanceUID:status:attributes:transferSyntax:)``,
which set Performed Procedure Step Status `(0040,0252)` but leave the rest of
the MPPS attribute set — long and modality-specific — to the caller, checked
with `DICOMModuleValidator` (in `DICOMKitAuthoring`, if the application also
links it).

## Topics

### DICOMweb

- ``DICOMwebClient``
- ``DICOMQIDOPagination``
- ``DICOMwebRetryPolicy``
- ``DICOMwebTransport``
- ``DICOMwebError``
- ``DICOMJSONDataset``
- ``DICOMJSONBulkDataResolver``

### DIMSE association

- ``DICOMAssociation``
- ``DICOMAssociationPolicy``
- ``DICOMAssociationNegotiation``
- ``DICOMAssociationRequest``
- ``DICOMAssociationAcceptance``
- ``DICOMAssociationRejection``
- ``DICOMPresentationContext``
- ``DICOMPresentationContextAcceptance``
- ``DICOMRoleSelection``
- ``DICOMUserIdentity``
- ``DICOMUserIdentityNegotiation``
- ``DICOMImplementationIdentification``
- ``DICOMAsynchronousOperationsWindow``
- ``DICOMULPDU``
- ``DICOMPDataValue``
- ``DICOMULTransport``
- ``NetworkDICOMULTransport``
- ``NetworkDICOMULListener``

### DIMSE services

- ``DICOMDIMSECommand``
- ``DICOMDIMSEStatus``
- ``DICOMDIMSERequest``
- ``DICOMSubOperationCounts``
- ``DICOMCFindResult``
- ``DICOMCMoveResult``
- ``DICOMCGetResult``
- ``DICOMCStoreRequest``
- ``DICOMNServiceResult``
- ``DICOMStorageCommitmentRequest``
- ``DICOMStorageCommitmentResult``
- ``DICOMStorageCommitmentFailure``
- ``DICOMStorageCommitmentError``
- ``DICOMPerformedProcedureStepStatus``

### Errors

- ``DICOMAssociationError``
- ``DICOMDIMSEError``
- ``DICOMULError``
- ``DICOMNetworkError``
